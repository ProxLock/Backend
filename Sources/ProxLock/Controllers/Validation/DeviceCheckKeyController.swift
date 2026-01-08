import Fluent
import Vapor
import JWTKit

struct DeviceCheckKeyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("me", "device-check")
        
        me.get(use: self.index)
        
        let keys = routes.grouped("me", "projects", ":projectID", "device-check")

        keys.post(use: self.create)
        keys.put(use: self.link)
        keys.get(use: self.get)
        keys.delete(use: self.delete)
    }

    /// GET /me/device-check
    ///
    /// Retrieves all DeviceCheck keys for a specific user.
    /// 
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter
    /// - Returns: Array of ``DeviceCheckKeySendingDTO`` objects containing DeviceCheck key information
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

    /// POST /me/projects/:projectID/device-check
    ///
    /// Creates or updates a DeviceCheck key for a specific project.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects a ``DeviceCheckKeyRecievingDTO`` object containing:
    /// - teamID: The Apple Developer team identifier (required)
    /// - keyID: The Apple Developer key identifier (required)
    /// - privateKey: The ES256 private key in PEM format (required)
    /// 
    /// ```json
    /// {
    ///   "teamID": "XYZ789GHI0",
    ///   "keyID": "ABC123DEF4",
    ///   "privateKey": "-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...\n-----END PRIVATE KEY-----"
    /// }
    /// ```
    /// 
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter and DeviceCheck key data in the request body
    /// - Returns: ``DeviceCheckKeySendingDTO`` object containing the DeviceCheck key information
    @Sendable
    func create(req: Request) async throws -> DeviceCheckKeySendingDTO {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await project.$user.load(on: req.db)
        
        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }
        
        try await project.$deviceCheckKey.load(on: req.db)
        
        let dto = try req.content.decode(DeviceCheckKeyRecievingDTO.self)
        
        guard let privateKey = dto.privateKey else {
            throw Abort(.badRequest, reason: "Missing private key")
        }
        
        // Validate key is correct form
        let _ = try ES256PrivateKey(pem: Data(privateKey.utf8))
        
        // Get required info from Play Integrity
        try await project.$playIntegrityConfig.load(on: req.db)
        
        let playIntegrityConfig = try? await project.$playIntegrityConfig.get(on: req.db)
        
        // Update Existing Key or Create New ONe
        let key: DeviceCheckKey
        
        if let foundKey = (try? await project.$deviceCheckKey.get(on: req.db)) {
            foundKey.secretKey = privateKey
            foundKey.keyID = dto.keyID
            foundKey.teamID = dto.teamID
            foundKey.bypassToken = playIntegrityConfig?.bypassToken ?? UUID().uuidString
            
            key = foundKey
        } else {
            key = DeviceCheckKey(secretKey: privateKey, keyID: dto.keyID, teamID: dto.teamID, bypassToken: playIntegrityConfig?.bypassToken ?? UUID().uuidString)
        }
        
        // Assign to user and save
        key.$project.id = try project.requireID()
        try await key.save(on: req.db)
        
        return key.toDTO()
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
    func link(req: Request) async throws -> DeviceCheckKeySendingDTO {
        // Get the key
        let user = try req.auth.require(User.self)
        let dto = try req.content.decode(DeviceCheckKeyRecievingDTO.self)
        
        try await user.$projects.load(on: req.db)
        let projects = try await user.$projects.get(on: req.db)
        
        var existingKey: DeviceCheckKey?
        
        for project in projects {
            try await project.$deviceCheckKey.load(on: req.db)
            
            guard let key = try await project.$deviceCheckKey.get(on: req.db),
                  dto.keyID == key.keyID,
                  dto.teamID == key.teamID
            else { continue }
            existingKey = key
        }
        
        guard let existingKey else {
            throw Abort(.notFound)
        }
        
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await project.$user.load(on: req.db)
        
        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }
        
        try await project.$deviceCheckKey.load(on: req.db)
        try await project.$playIntegrityConfig.load(on: req.db)
        
        let playIntegrityConfig = try? await project.$playIntegrityConfig.get(on: req.db)
        
        let key: DeviceCheckKey
        
        if let foundKey = (try? await project.$deviceCheckKey.get(on: req.db)) {
            foundKey.secretKey = existingKey.secretKey
            foundKey.keyID = existingKey.keyID
            foundKey.teamID = existingKey.teamID
            foundKey.bypassToken = playIntegrityConfig?.bypassToken ?? UUID().uuidString
            
            key = foundKey
        } else {
            key = DeviceCheckKey(secretKey: existingKey.secretKey, keyID: existingKey.keyID, teamID: existingKey.teamID, bypassToken: playIntegrityConfig?.bypassToken ?? UUID().uuidString)
        }
        
        // Assign to user and save
        key.$project.id = try project.requireID()
        try await key.save(on: req.db)
        
        return key.toDTO()
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
    func get(req: Request) async throws -> DeviceCheckKeySendingDTO {
        let user = try req.auth.require(User.self)
        guard let projectID = req.parameters.get("projectID", as: UUID.self), let project = try await Project.find(projectID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await project.$user.load(on: req.db)
        
        guard try await user.requireID() == project.$user.get(on: req.db).requireID() else {
            throw Abort(.notFound)
        }
        
        try await project.$deviceCheckKey.load(on: req.db)
        
        guard let key = try await project.$deviceCheckKey.get(on: req.db) else {
            throw Abort(.notFound)
        }
        
        return key.toDTO()
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
        
        try await project.$deviceCheckKey.load(on: req.db)
        
        guard let key = try await project.$deviceCheckKey.get(on: req.db) else {
            throw Abort(.notFound)
        }

        try await key.delete(on: req.db)
        return .accepted
    }
}
