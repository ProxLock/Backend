import Fluent
import Vapor

struct UserAPIKeyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("me", "api-keys")
        
        users.post(use: self.create)
        users.delete(use: self.delete)
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
    /// - Returns: ``UserDTO`` object containing the created user information
    @Sendable
    func create(req: Request) async throws -> UserAPIKeyDTO {
        let user = try req.auth.require(User.self)
        try await user.$apiKeys.load(on: req.db)
        let allKeys = try await user.$apiKeys.get(on: req.db)
        
        guard allKeys.count+1 <= user.currentSubscription?.userApiKeyLimit ?? SubscriptionPlans.free.userApiKeyLimit else {
            throw Abort(.forbidden, reason: "User API Key Limit Reached.")
        }
        let dto = try req.content.decode(UserAPIKeyDTO.self)
        guard let name = dto.name else {
            throw Abort(.badRequest, reason: "Name is required.")
        }
        
        let key = User.APIKey(name: name)
        key.$user.id = try user.requireID()
        
        try await key.save(on: req.db)
        
        return try key.toDTO()
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
    ///   - req: The HTTP request containing the user ID parameter
    /// - Returns: HTTP status code indicating the result of the deletion operation
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let dto = try req.content.decode(UserAPIKeyDTO.self)
        
        guard let dtoKey = dto.key else {
            throw Abort(.badRequest, reason: "Missing API Key.")
        }
        
        let key = try await User.APIKey.query(on: req.db).filter(\.$id == dtoKey).filter(\.$user.$id == user.requireID()).with(\.$user).first()
        
        try await key?.delete(on: req.db)
        
        return .accepted
    }
}
