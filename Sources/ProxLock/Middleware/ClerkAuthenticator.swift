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
import JWTKit

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
            
            try validateAdminAccess(for: request, with: claims)
            // Impersonate user if success with admin route
            if let userID = request.parameters.get("userID"), request.url.path.contains("/admin"), Constants.adminClerkIDs.contains(claims.id) {
                guard let user = try await User.query(on: request.db).filter(\.$clerkID == userID).first() else {
                    throw Errors.userNotFound
                }
                request.auth.login(user)
            }
            
            guard let user = try await User.query(on: request.db).filter(\.$clerkID == claims.id).first() else {
                throw Errors.userNotFound
            }
            request.auth.login(user)
        } catch {
            request.logger.warning("Invalid Clerk token: \(error)")
            throw error
        }
    }
    
    func validateAdminAccess(for request: Request, with claims: ClerkClaims) throws {
        if request.url.path.contains("/admin"), !Constants.adminClerkIDs.contains(claims.id) {
            throw Abort(.unauthorized)
        }
    }
    
    static func verifyClerkToken(_ token: String, on req: Request) async throws -> ClerkClaims {
        do {
            return try await Self.verifyProdClerkToken(token, on: req)
        } catch {
            do {
                return try await Self.verifyDevClerkToken(token, on: req)
            } catch {
                throw error
            }
        }
    }
    
    private static func verifyProdClerkToken(_ token: String, on req: Request) async throws -> ClerkClaims {
        // Fetch Clerk JWKS
        let jwksURL = URI(string: "https://clerk.proxlock.dev/.well-known/jwks.json")
        let jwks = try await req.client.get(jwksURL).content.decode(JWKS.self)

        let signers = try await req.application.jwt.keys.add(jwks: jwks)

        // Verify JWT
        return try await signers.verify(token, as: ClerkClaims.self)
    }
    
    private static func verifyDevClerkToken(_ token: String, on req: Request) async throws -> ClerkClaims {
        // Fetch Clerk JWKS
        let jwksURL = URI(string: "https://fit-quail-72.clerk.accounts.dev/.well-known/jwks.json")
        let jwks = try await req.client.get(jwksURL).content.decode(JWKS.self)

        let signers = try await req.application.jwt.keys.add(jwks: jwks)

        // Verify JWT
        return try await signers.verify(token, as: ClerkClaims.self)
    }
}
