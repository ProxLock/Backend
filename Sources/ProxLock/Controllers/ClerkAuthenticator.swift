//
//  ClerkAuthenticator.swift
//  ProxLock
//
//  Created by Morris Richman on 10/21/25.
//

import Foundation
import Vapor
import Fluent
import JWT

struct ClerkClaims: JWTPayload {
    var id: String
    var exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

struct ClerkAuthenticator: AsyncBearerAuthenticator {
    enum Errors: Error {
        case userNotFound
    }
    
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        do {
            let claims = try await Self.verifyClerkToken(bearer.token, on: request)
            
            guard let user = try await User.query(on: request.db).filter(\.$clerkID == claims.id).first() else {
                throw Errors.userNotFound
            }
            request.auth.login(user)
        } catch {
            request.logger.warning("Invalid Clerk token: \(error)")
        }
    }
    
    static func verifyClerkToken(_ token: String, on req: Request) async throws -> ClerkClaims {
        // Fetch Clerk JWKS
        let jwksURL = URI(string: "https://fit-quail-72.clerk.accounts.dev/.well-known/jwks.json")
        let jwks = try await req.client.get(jwksURL).content.decode(JWKS.self)

        let signers = try await req.application.jwt.keys.add(jwks: jwks)

        // Verify JWT
        return try await signers.verify(token, as: ClerkClaims.self)
    }
}
