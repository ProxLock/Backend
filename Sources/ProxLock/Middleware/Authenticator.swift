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

struct Authenticator: AsyncBearerAuthenticator {
    enum Errors: Error {
        case userNotFound
    }
    
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        if bearer.token.hasPrefix("sk_") {
            try await handleAPIKeyAuth(bearer: bearer, for: request)
            return
        }
        
        try await handleClerkAuth(bearer: bearer, for: request)
    }
    
    private func handleAPIKeyAuth(bearer: BearerAuthorization, for request: Request) async throws {
        guard let key = try await User.AccessKey.find(bearer.token, on: request.db) else {
            throw Errors.userNotFound
        }
        try await key.$user.load(on: request.db)
        let user = try await key.$user.get(on: request.db)
        
        guard try await !didImpersonateFromAdmin(for: request, adminUserID: user.clerkID) else {
            return
        }
        
        request.auth.login(user)
    }
    
    private func handleClerkAuth(bearer: BearerAuthorization, for request: Request) async throws {
        do {
            let claims = try await Self.verifyClerkToken(bearer.token, on: request)
            
            try validateAdminAccess(for: request, with: claims)
            // Impersonate user if success with admin route
            guard try await !didImpersonateFromAdmin(for: request, adminUserID: claims.id) else {
                return
            }
            
            guard let user = try await User.query(on: request.db).filter(\.$clerkID == claims.id).first() else {
                throw Errors.userNotFound
            }
            request.auth.login(user)
        } catch {
            request.logger.warning("Invalid Clerk token: \(error)")
        }
    }
    
    private func validateAdminAccess(for request: Request, with claims: ClerkClaims) throws {
        if request.url.path.contains("/admin"), !Constants.adminClerkIDs.contains(claims.id) {
            throw Abort(.unauthorized)
        }
    }
    
    private func didImpersonateFromAdmin(for request: Request, adminUserID: String) async throws -> Bool {
        guard request.url.path.contains("/admin") else {
            return false
        }
        
        guard let userID = request.parameters.get("userID") else {
            return false
        }
        
        guard let user = try await User.query(on: request.db).filter(\.$clerkID == userID).first() else {
            throw Errors.userNotFound
        }
        
        request.auth.login(user)
        return true
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
