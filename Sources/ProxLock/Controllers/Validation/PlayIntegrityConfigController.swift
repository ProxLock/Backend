import Core
import Fluent
import JWTKit
import Vapor

struct PlayIntegrityConfigController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("me", "play-integrity")

        me.get(use: self.index)

        let keys = routes.grouped("me", "projects", ":projectID", "play-integrity")

        keys.post(use: self.create)
        keys.patch(use: self.update)
        keys.put(use: self.link)
        keys.get(use: self.get)
        keys.delete(use: self.delete)
    }

    /// GET /me/play-integrity
    ///
    /// Retrieves all PlayIntegrity configurations for a specific user.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter
    /// - Returns: Array of ``PlayIntegrityConfigSendingDTO`` objects containing PlayIntegrity configuration information
    @Sendable
    func index(req: Request) async throws -> [PlayIntegrityConfigSendingDTO] {
        let user = try req.auth.require(User.self)

        try await user.$projects.load(on: req.db)
        let projects = try await user.$projects.get(on: req.db)

        var configs: [PlayIntegrityConfig] = []

        for project in projects {
            try await project.$playIntegrityConfig.load(on: req.db)

            guard let config = try await project.$playIntegrityConfig.get(on: req.db),
                !configs.contains(where: { $0.gcloudJson == config.gcloudJson })
            else { continue }
            configs.append(config)
        }

        return configs.map { try? $0.toDTO() }.compactMap({ $0 })
    }

    /// POST /me/projects/:projectID/play-integrity
    ///
    /// Creates or updates a DeviceCheck key for a specific project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects a the Google Cloud service account's key json object containing.
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter and DeviceCheck key data in the request body
    /// - Returns: ``PlayIntegrityConfigSendingDTO`` object containing PlayIntegrity configuration information
    @Sendable
    func create(req: Request) async throws -> PlayIntegrityConfigSendingDTO {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
            let project = try await Project.find(projectID, on: req.db)
        else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)

        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }

        try await project.$deviceCheckKey.load(on: req.db)
        try await project.$playIntegrityConfig.load(on: req.db)

        let gcloudJson = try req.content.decode(PlayIntegrityConfigRecievingDTO.self)

        let config = try await setConfig(gcloudJson, on: project, from: req)
        return try config.toDTO()
    }

    /// PATCh /me/projects/:projectID/play-integrity
    ///
    /// Links an existing PlayIntegrity configuration to a different project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects a ``PlayIntegrityConfigLinkRecievingDTO`` object containing:
    /// - projectID: The project ID to copy the PlayIntegrity configuration from (required)
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the project ID parameter and link data in the request body
    /// - Returns: ``PlayIntegrityConfigSendingDTO`` object containing the PlayIntegrity configuration information
    @Sendable
    func update(req: Request) async throws -> PlayIntegrityConfigSendingDTO {
        // Get the key
        let user = try req.auth.require(User.self)
        let dto = try req.content.decode(PlayIntegrityConfigRecievingDTO.self)

        guard let project = try await Project.find(req.parameters.require("projectID"), on: req.db) else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)
        guard try await project.$user.get(on: req.db).requireID() == user.requireID() else {
            throw Abort(.notFound)
        }

        try await project.$playIntegrityConfig.load(on: req.db)
        let existingConfig = try await project.$playIntegrityConfig.get(on: req.db)

        guard let existingConfig else {
            throw Abort(.notFound)
        }

        if let packageName = dto.packageName {
            existingConfig.packageName = packageName
        }
        
        if let allowedAppRecognitionVerdicts = dto.allowedAppRecognitionVerdicts {
            existingConfig.allowedAppRecognitionVerdicts = allowedAppRecognitionVerdicts
        }
        
        try await existingConfig.save(on: req.db)

        return try existingConfig.toDTO()
    }

    /// PUT /me/projects/:projectID/play-integrity
    ///
    /// Links an existing PlayIntegrity configuration to a different project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects a ``PlayIntegrityConfigLinkRecievingDTO`` object containing:
    /// - projectID: The project ID to copy the PlayIntegrity configuration from (required)
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the project ID parameter and link data in the request body
    /// - Returns: ``PlayIntegrityConfigSendingDTO`` object containing the PlayIntegrity configuration information
    @Sendable
    func link(req: Request) async throws -> PlayIntegrityConfigSendingDTO {
        // Get the key
        let user = try req.auth.require(User.self)
        let dto = try req.content.decode(PlayIntegrityConfigLinkRecievingDTO.self)

        guard let project = try await Project.find(dto.projectID, on: req.db) else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)
        guard try await project.$user.get(on: req.db).requireID() == user.requireID() else {
            throw Abort(.notFound)
        }

        try await project.$playIntegrityConfig.load(on: req.db)
        let existingConfig = try await project.$playIntegrityConfig.get(on: req.db)

        guard let existingConfig else {
            throw Abort(.notFound)
        }

        guard let projectID = req.parameters.get("projectID", as: UUID.self),
            let project = try await Project.find(projectID, on: req.db)
        else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)

        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }

        let config = try await setConfig(PlayIntegrityConfigRecievingDTO(packageName: existingConfig.packageName, gcloudJson: existingConfig.configData, allowedAppRecognitionVerdicts: existingConfig.allowedAppRecognitionVerdicts), on: project, from: req)

        return try config.toDTO()
    }

    /// GET /me/projects/:projectID/play-integrity
    ///
    /// Retrieves the PlayIntegrity configuration for a specific project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the project ID parameter
    /// - Returns: ``PlayIntegrityConfigSendingDTO`` object containing the PlayIntegrity configuration information
    @Sendable
    func get(req: Request) async throws -> PlayIntegrityConfigSendingDTO {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
            let project = try await Project.find(projectID, on: req.db)
        else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)

        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }

        try await project.$playIntegrityConfig.load(on: req.db)

        guard let config = try await project.$playIntegrityConfig.get(on: req.db) else {
            throw Abort(.notFound)
        }

        return try config.toDTO()
    }

    /// DELETE /me/projects/:projectID/play-integrity
    ///
    /// Deletes the PlayIntegrity configuration for a specific project.
    ///
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the project ID parameter
    /// - Returns: HTTP status code indicating the result of the deletion operation
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
            let project = try await Project.find(projectID, on: req.db)
        else {
            throw Abort(.notFound)
        }

        try await project.$user.load(on: req.db)

        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }

        try await project.$playIntegrityConfig.load(on: req.db)

        guard let config = try await project.$playIntegrityConfig.get(on: req.db) else {
            throw Abort(.notFound)
        }

        try await config.delete(on: req.db)
        return .accepted
    }

    // MARK: - Private Functions

    /// Sets the ``PlayIntegrityConfig`` for a project using the Google Cloud service account credentials.
    ///
    /// If an existing configuration is found, it updates the credentials. Otherwise, it creates a new configuration.
    /// The bypass token is shared with the DeviceCheck key if one exists, otherwise a new UUID is generated.
    ///
    /// - Parameters:
    ///   - gcloudJson: The Google Cloud service account credentials object
    ///   - project: The project to configure PlayIntegrity for
    ///   - req: The HTTP request for database access
    /// - Returns: The created or updated ``PlayIntegrityConfig``
    func setConfig(
        _ dto: PlayIntegrityConfigRecievingDTO, on project: Project, from req: Request
    ) async throws -> PlayIntegrityConfig {
        guard let gcloudJson = dto.gcloudJson else {
            throw Abort(.badRequest, reason: "Missing required 'gcloudJson' field")
        }
        guard let packageName = dto.packageName else {
            throw Abort(.badRequest, reason: "Missing required 'packageName' field")
        }
        
        try await project.$deviceCheckKey.load(on: req.db)
        try await project.$playIntegrityConfig.load(on: req.db)

        let deviceCheckKey = try? await project.$deviceCheckKey.get(on: req.db)

        // Update Existing Key or Create New ONe
        let config: PlayIntegrityConfig

        if let foundConfig = (try? await project.$playIntegrityConfig.get(on: req.db)) {
            foundConfig.gcloudJson = try gcloudJson.asString()
            foundConfig.bypassToken = deviceCheckKey?.bypassToken ?? UUID().uuidString
            foundConfig.allowedAppRecognitionVerdicts = dto.allowedAppRecognitionVerdicts ?? [.playRecognized]
            config = foundConfig
        } else {
            config = PlayIntegrityConfig(
                packageName: packageName,
                gcloudJson: try gcloudJson.asString(),
                bypassToken: deviceCheckKey?.bypassToken ?? UUID().uuidString,
                allowedAppRecognitionVerdicts: dto.allowedAppRecognitionVerdicts ?? [.playRecognized]
            )
        }

        // Assign to user and save
        config.$project.id = try project.requireID()
        try await config.save(on: req.db)
        
        // Link to Keys
        Task {
            do {
                try await project.$apiKeys.load(on: req.db)
                let keys = try await project.$apiKeys.get(on: req.db)
                
                for key in keys {
                    key.$playIntegrityConfig.id = try config.requireID()
                    try await key.save(on: req.db)
                }
            } catch {
                req.logger.error("Error Linking PlayIntegrityConfig to API Keys: \(error)")
            }
        }

        return config
    }
}

extension GoogleServiceAccountCredentials {
    func asString() throws -> String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        guard let string = String(data: try jsonEncoder.encode(self), encoding: .utf8) else {
            throw Abort(
                .internalServerError, reason: "Unable to serialize Google Cloud credentials")
        }
        return string
    }
}
