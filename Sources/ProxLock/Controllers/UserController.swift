import Fluent
import Vapor

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("me")
        
        users.post(use: self.create)
        users.get(use: self.get)
        users.delete(use: self.delete)
        
        let adminRoute = routes.grouped("user")
        
        adminRoute.post(use: self.create)
        adminRoute.get(use: self.get)
        adminRoute.delete(use: self.delete)
    }

    /// POST /me
    ///
    /// Creates a new user account.
    /// 
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing user data in the request body
    /// - Returns: ``UserDTO`` object containing the created user information
    @Sendable
    func create(req: Request) async throws -> UserDTO {
        if let user = (try? req.auth.require(User.self)) {
            return try await user.toDTO(on: req.db)
        }
        
        guard let bearer = req.headers.bearerAuthorization else {
            throw Abort(.unauthorized)
        }
        
        let claims = try await ClerkAuthenticator.verifyClerkToken(bearer.token, on: req)
        
        guard !claims.id.isEmpty else {
            throw Abort(.unauthorized)
        }

        let user = User(clerkID: claims.id)
        try await user.save(on: req.db)
        
        var dto = try await user.toDTO(on: req.db)
        dto.justRegistered = true
        
        return dto
    }
    
    /// GET /me
    ///
    /// Retrieves a specific user by their bearer token.
    ///
    /// ## Required Headers
    /// - Expects a bearer token object from Clerk. More information here: https://clerk.com/docs/react/reference/hooks/use-auth
    ///
    /// - Parameters:
    ///   - req: The HTTP request containing the user ID parameter
    /// - Returns: ``UserDTO`` object containing the user information
    @Sendable
    func get(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        
        return try await user.toDTO(on: req.db)
    }

    /// DELETE /me
    ///
    /// Deletes a specific user by their bearer token.
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

        try await user.delete(on: req.db)
        return .accepted
    }
}
