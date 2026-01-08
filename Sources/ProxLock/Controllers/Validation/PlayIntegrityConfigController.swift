import Fluent
import Vapor
import JWTKit

struct PlayIntegrityConfigController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("me", "play-integrity")
        
        me.get(use: self.index)
        
        let keys = routes.grouped("me", "projects", ":projectID", "play-integrity")

        keys.post(use: self.create)
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
    func index(req: Request) async throws -> [DeviceCheckKeySendingDTO] {
        let user = try req.auth.require(User.self)
        
        try await user.$projects.load(on: req.db)
        let projects = try await user.$projects.get(on: req.db)
        
        var keys: [DeviceCheckKey] = []
        
        for project in projects {
            try await project.$deviceCheckKey.load(on: req.db)
            
            guard let key = try await project.$deviceCheckKey.get(on: req.db),
                  !keys.contains(where: { $0.keyID == key.keyID && $0.teamID == key.teamID })
            else { continue }
            keys.append(key)
        }
        
        return keys.map { $0.toDTO() }
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
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await project.$user.load(on: req.db)
        
        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }
        
        try await project.$deviceCheckKey.load(on: req.db)
        try await project.$playIntegrityConfig.load(on: req.db)
        
        let gcloudJson = try req.content.decode(String.self)
        let deviceCheckKey = try? await project.$deviceCheckKey.get(on: req.db)
        
        let config = try await setConfig(gcloudJson, on: project, from: req)
        return config.toDTO()
    }

    /// PUT /me/projects/:projectID/device-check
    ///
    /// Creates or updates a DeviceCheck key for a specific project by copying an existing key from the user.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects a ``DeviceCheckKeyRecievingDTO`` object containing:
    /// - teamID: The Apple Developer team identifier (required)
    /// - keyID: The Apple Developer key identifier (required)
    /// 
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter and DeviceCheck key data in the request body
    /// - Returns: ``DeviceCheckKeySendingDTO`` object containing the DeviceCheck key information
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
        
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await project.$user.load(on: req.db)
        
        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }
        
        let config = try await setConfig(existingConfig.gcloudJson, on: project, from: req)
        
        return config.toDTO()
    }

    /// GET /me/projects/:projectID/device-check
    ///
    /// Retrieves a specific DeviceCheck key by team ID for a project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Path Parameters
    /// - teamID: The unique identifier of the Apple Developer team
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID and team ID parameters
    /// - Returns: ``DeviceCheckKeySendingDTO`` object containing the DeviceCheck key information
    @Sendable
    func get(req: Request) async throws -> PlayIntegrityConfigSendingDTO {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
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
        
        return config.toDTO()
    }

    /// DELETE /me/projects/:projectID/device-check
    ///
    /// Deletes a specific DeviceCheck key by team ID for a project.
    ///
    /// ## Path Parameters
    /// - teamID: The unique identifier of the Apple Developer team 
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID and team ID parameters
    /// - Returns: HTTP status code indicating the result of the deletion operation
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
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
    
    /// Sets the ``PlayIntegrityConfig`` for a project using the Google Cloud service account's json
    func setConfig(_ gcloudJson: String, on project: Project, from req: Request) async throws -> PlayIntegrityConfig {
        try await project.$deviceCheckKey.load(on: req.db)
        try await project.$playIntegrityConfig.load(on: req.db)
        
        let gcloudJson = try req.content.decode(String.self)
        let deviceCheckKey = try? await project.$deviceCheckKey.get(on: req.db)
        
        // Update Existing Key or Create New ONe
        let config: PlayIntegrityConfig
        
        if let foundConfig = (try? await project.$playIntegrityConfig.get(on: req.db)) {
            foundConfig.gcloudJson = gcloudJson
            foundConfig.bypassToken = deviceCheckKey?.bypassToken ?? UUID().uuidString
            config = foundConfig
        } else {
            config = PlayIntegrityConfig(gcloudJson: gcloudJson, bypassToken: deviceCheckKey?.bypassToken ?? UUID().uuidString)
        }
        
        // Assign to user and save
        config.$project.id = try project.requireID()
        try await config.save(on: req.db)
        
        return config
    }
}
