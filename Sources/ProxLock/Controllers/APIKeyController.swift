import Fluent
import Vapor

struct APIKeyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let keys = routes.grouped("me", "projects", ":projectID", "keys")

        keys.get(use: self.index)
        keys.post(use: self.create)
        keys.group(":keyID") { key in
            key.get(use: self.get)
            key.put(use: self.update)
            key.delete(use: self.delete)
        }
        
        let adminEndpoint = routes.grouped(":userID", "keys")
        adminEndpoint.post("override-limit", use: self.overrideLimit)
    }

    /// GET /me/projects/:projectID/keys
    ///
    /// Retrieves all API keys for a specific project belonging to a user.
    ///
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project 
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    /// 
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID and project ID parameters
    /// - Returns: Array of ``APIKeySendingDTO`` objects containing API key information
    @Sendable
    func index(req: Request) async throws -> [APIKeySendingDTO] {
        let user = try req.auth.require(User.self)
        
        guard let projectIDString = req.parameters.get("projectID"),
                let projectID = UUID(uuidString: projectIDString),
              let project = try await Project.query(on: req.db).filter(\.$id == projectID).filter(\.$user.$id == user.requireID()).with(\.$user).first() else {
            throw Abort(.notFound)
        }
        
        return try await APIKey.query(on: req.db).filter(\.$project.$id == project.requireID()).all().map { $0.toDTO() }
    }

    /// POST /me/projects/:projectID/keys
    ///
    /// Creates a new API key for a specific project belonging to a user.
    /// 
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// ## Request Body
    /// Expects an ``APIKeyRecievingDTO`` object containing:
    /// - name: The name of the API key
    /// - apiKey: The full API key to be split and stored
    /// - description: Optional description of the API key (optional)
    /// 
    /// ```json
    /// {
    ///   "name": "My API Key",
    ///   "apiKey": "sk-1234567890abcdef...",
    ///   "description": "Optional description"
    /// }
    /// ```
    /// 
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID, project ID parameters, and API key data in the request body
    /// - Returns: ``APIKeySendingDTO`` object containing the created API key information with the user's partial key
    @Sendable
    func create(req: Request) async throws -> APIKeySendingDTO {
        let user = try req.auth.require(User.self)
        
        guard let projectIDString = req.parameters.get("projectID"),
                let projectID = UUID(uuidString: projectIDString),
              let project = try await Project.query(on: req.db).filter(\.$id == projectID).filter(\.$user.$id == user.requireID()).with(\.$user).first() else {
            throw Abort(.notFound)
        }
        try await project.$apiKeys.load(on: req.db)
        let apiKeys = try await project.$apiKeys.get(on: req.db)
        
        guard apiKeys.count + 1 <= user.overrideAPIKeyLimit ?? (user.currentSubscription ?? .free).keyLimit || user.overrideProjectLimit ?? (user.currentSubscription ?? .free).projectLimit <= -1 else {
            throw Abort(.paymentRequired, reason: "API Key limit reached for project. Upgrade your plan to increase this limit.")
        }
        
        let keyDTO = try req.content.decode(APIKeyRecievingDTO.self)
        
        guard let apiKey = keyDTO.apiKey else {
            throw Abort(.badRequest, reason: "API key is required")
        }
        
        guard let name = keyDTO.name else {
            throw Abort(.badRequest, reason: "Name for API key is required")
        }
        
        let (userKey, dbKey) = try KeySplitter.split(key: apiKey)
        
        let key = APIKey(name: name, description: keyDTO.description ?? "", partialKey: dbKey, rateLimit: keyDTO.rateLimit, allowsWeb: keyDTO.allowsWeb ?? false, whitelistedUrls: keyDTO.whitelistedUrls ?? [])

        key.$project.id = try project.requireID()
        key.$user.id = try user.requireID()
        
        // Set Device Validation
        try await project.$deviceCheckKey.load(on: req.db)
        let deviceCheckKey = try await project.$deviceCheckKey.get(on: req.db)
        key.$deviceCheckKey.id = try deviceCheckKey?.requireID()
        
        try await project.$playIntegrityConfig.load(on: req.db)
        let playIntegrityConfig = try await project.$playIntegrityConfig.get(on: req.db)
        key.$playIntegrityConfig.id = try playIntegrityConfig?.requireID()

        try await key.save(on: req.db)
        
        // Construct return dto
        var dto = key.toDTO()
        // Add key to dto just for creation
        dto.userPartialKey = userKey
        
        return dto
    }

    /// PUT /me/projects/:projectID/keys/:keyID
    ///
    /// Updates a specific API key by its unique identifier.
    ///
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    /// - keyID: The unique identifier of the API key
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID, project ID, and key ID parameters
    /// - Returns: ``APIKeySendingDTO`` object containing the API key information
    @Sendable
    func update(req: Request) async throws -> APIKeySendingDTO {
        let user = try req.auth.require(User.self)
        let keyDTO = try req.content.decode(APIKeyRecievingDTO.self)
        
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
              let project = try await Project.query(on: req.db).filter(\.$id == projectID).filter(\.$user.$id == user.requireID()).with(\.$user).first() else {
            throw Abort(.notFound)
        }

        guard let keyID = req.parameters.get("keyID", as: UUID.self),
              let key = try await APIKey.query(on: req.db).filter(\.$id == keyID).filter(\.$project.$id == project.requireID()).with(\.$project).first() else {
            throw Abort(.notFound)
        }
        
        if let name = keyDTO.name {
            guard !name.isEmpty else {
                throw Abort(.badRequest, reason: "API key name cannot be empty")
            }
            key.name = name
        }
        
        if let description = keyDTO.description {
            key.userDescription = description
        }
        
        if let whitelistedUrls = keyDTO.whitelistedUrls {
            key.whitelistedUrls = whitelistedUrls
        }
        
        if let rateLimit = keyDTO.rateLimit {
            key.setRateLimit(rateLimit)
        }
        
        if let allowsWeb = keyDTO.allowsWeb {
            key.allowsWeb = allowsWeb
        }
        
        key.$user.id = try user.requireID()
        
        // Set Device Validation
        try await project.$deviceCheckKey.load(on: req.db)
        let deviceCheckKey = try await project.$deviceCheckKey.get(on: req.db)
        key.$deviceCheckKey.id = try deviceCheckKey?.requireID()
        
        try await project.$playIntegrityConfig.load(on: req.db)
        let playIntegrityConfig = try await project.$playIntegrityConfig.get(on: req.db)
        key.$playIntegrityConfig.id = try playIntegrityConfig?.requireID()
        
        try await key.save(on: req.db)

        return key.toDTO()
    }

    /// GET /me/projects/:projectID/keys/:keyID
    ///
    /// Retrieves a specific API key by its unique identifier.
    /// 
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    /// - keyID: The unique identifier of the API key
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID, project ID, and key ID parameters
    /// - Returns: ``APIKeySendingDTO`` object containing the API key information
    @Sendable
    func get(req: Request) async throws -> APIKeySendingDTO {
        let user = try req.auth.require(User.self)
        
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
              let project = try await Project.query(on: req.db).filter(\.$id == projectID).filter(\.$user.$id == user.requireID()).with(\.$user).first() else {
            throw Abort(.notFound)
        }

        guard let keyID = req.parameters.get("keyID", as: UUID.self),
              let key = try await APIKey.query(on: req.db).filter(\.$id == keyID).filter(\.$project.$id == project.requireID()).with(\.$project).first() else {
            throw Abort(.notFound)
        }

        return key.toDTO()
    }

    /// DELETE /me/projects/:projectID/keys/:keyID
    ///
    /// Deletes a specific API key by its unique identifier.
    /// 
    /// ## Path Parameters
    /// - projectID: The unique identifier of the project
    /// - keyID: The unique identifier of the API key
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID, project ID, and key ID parameters
    /// - Returns: HTTP status code indicating the result of the deletion operation
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        
        guard let projectID = req.parameters.get("projectID", as: UUID.self),
              let project = try await Project.query(on: req.db).filter(\.$id == projectID).filter(\.$user.$id == user.requireID()).with(\.$user).first() else {
            throw Abort(.notFound)
        }

        guard let keyID = req.parameters.get("keyID", as: UUID.self),
              let key = try await APIKey.query(on: req.db).filter(\.$id == keyID).filter(\.$project.$id == project.requireID()).with(\.$project).first() else {
            throw Abort(.notFound)
        }

        try await key.delete(on: req.db)
        return .accepted
    }
    
    // MARK: - Admin Functions
    /// POST /admin/:userID/keys/override-limit
    ///
    /// Sets the key per project override limit for a user.
    ///
    /// ## Body
    /// Send an integer to set the limit or null to remove the limit.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing user data in the request body
    /// - Returns: ``UserDTO`` object containing the created user information
    @Sendable
    func overrideLimit(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        
        let value = try? req.content.decode(Int.self)
        
        user.overrideAccessKeyLimit = value
        try await user.save(on: req.db)
        
        return try await user.toDTO(on: req.db)
    }
}
