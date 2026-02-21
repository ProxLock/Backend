import Fluent
import Vapor

struct UserAccessKeyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("me", "api-keys")
        
        users.post(use: self.create)
        users.delete(use: self.delete)
        
        let adminUsers = routes.grouped(":userID", "user", "api-keys")
        
        adminUsers.post(use: self.create)
        adminUsers.delete(use: self.delete)
        adminUsers.post("override-limit", use: self.overrideLimit)
    }

    /// POST /me/api-keys
    ///
    /// Creates a new ProxLock api key for a user.
    ///
    /// ## Required Body
    /// ``UserAPIKeyDTO`` object with a valid id.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing user data in the request body
    /// - Returns: ``UserAPIKeyDTO`` object containing the created API key information
    @Sendable
    func create(req: Request) async throws -> UserAPIKeyDTO {
        let user = try req.auth.require(User.self)
        try await user.$accessKey.load(on: req.db)
        let allKeys = try await user.$accessKey.get(on: req.db)
        
        let maxUsage = user.overrideAccessKeyLimit ?? (user.currentSubscription?.userApiKeyLimit ?? SubscriptionPlans.free.userApiKeyLimit)
        
        guard allKeys.count+1 <= maxUsage || maxUsage <= -1 else {
            throw Abort(.paymentRequired, reason: "User Access limit reached. Upgrade your plan to increase this limit.")
        }
        let dto = try req.content.decode(UserAPIKeyDTO.self)
        guard let name = dto.name else {
            throw Abort(.badRequest, reason: "Name is required.")
        }
        
        let secretKey = "sk_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        
        let dbKey = try User.AccessKey(name: name, key: secretKey)
        dbKey.$user.id = try user.requireID()
        
        try await dbKey.save(on: req.db)
        
        return try dbKey.toDTO()
    }

    /// DELETE /me/api-keys
    ///
    /// Deletes a specific access api key for a user.
    ///
    /// ## Required Body
    /// ``UserAPIKeyDTO`` object with a valid id.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the API key to delete in the request body
    /// - Returns: HTTP status code indicating the result of the deletion operation
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let dto = try req.content.decode(UserAPIKeyDTO.self)
        
        guard let dtoKey = dto.key else {
            throw Abort(.badRequest, reason: "Missing API Key.")
        }
        
        let key = try await User.AccessKey.query(on: req.db).filter(\.$id == dtoKey).filter(\.$user.$id == user.requireID()).with(\.$user).first()
        
        try await key?.delete(on: req.db)
        
        return .accepted
    }
    
    // MARK: - Admin Functions
    /// POST /admin/:userID/user/api-keys/override-limit
    ///
    /// Sets the access key override limit for a user.
    ///
    /// ## Required Body
    /// An optional `Int` that sets the limit
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
