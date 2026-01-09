//
//  DeviceValidationMiddleware.swift
//  APIProxy
//
//  Created by Morris Richman on 10/10/25.
//

import Foundation
import Vapor
import VaporDeviceCheck
import Fluent
import JWTKit

struct DeviceValidationMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let modeString = request.headers.first(name: DeviceValidationHeaderKeys.validationMode), let mode = DeviceValidationMode(rawValue: modeString) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Mode not detected")
        }
        
        switch mode {
        case .deviceCheck:
            return try await handleDeviceCheck(to: request, chainingTo: next)
        case .web:
            return try await handleWeb(to: request, chainingTo: next)
        }
    }
    
    private func handleWeb(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let associationId = request.headers.first(name: ProxyHeaderKeys.associationId) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Association ID not detected")
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await APIKey.find(UUID(uuidString: associationId), on: request.db) else {
            throw Abort(.unauthorized, reason: "Key was not found")
        }
        
        guard dbKey.allowsWeb else {
            throw Abort(.unauthorized, reason: "Web requests are not enabled for this key")
        }
        
        let deviceCheckEventLoopFuture = wildcardCorsMiddleware.respond(to: request, chainingTo: next)
        
        let response = try await withCheckedThrowingContinuation { continuation in
            deviceCheckEventLoopFuture.whenComplete { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return response
    }
    
    private func handleDeviceCheck(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let associationId = request.headers.first(name: ProxyHeaderKeys.associationId) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Association ID not detected")
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await APIKey.find(UUID(uuidString: associationId), on: request.db) else {
            throw Abort(.unauthorized, reason: "Key was not found")
        }
        try await dbKey.$project.load(on: request.db)
        let project = try await dbKey.$project.get(on: request.db)
        
        try await project.$deviceCheckKey.load(on: request.db)
        guard let key = try await project.$deviceCheckKey.get(on: request.db) else {
            throw Abort(.unauthorized, reason: "Key was not found")
        }
        
        let kid = JWKIdentifier(string: key.keyID)
        let privateKey = try ES256PrivateKey(pem: Data(key.secretKey.utf8))
        
        // Add ECDSA key with JWKIdentifier
        await request.application.jwt.keys.add(ecdsa: privateKey, kid: kid)
        
        let deviceCheckMiddleware = DeviceCheck(
            jwkKid: kid,
            jwkIss: key.teamID,
            excludes: [["health"]],
            bypassTokens: [key.bypassToken]
        )
        
        let deviceCheckEventLoopFuture = deviceCheckMiddleware.respond(to: request, chainingTo: next)
        
        let response = try await withCheckedThrowingContinuation { continuation in
            deviceCheckEventLoopFuture.whenComplete { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        return response
    }
}

struct DeviceValidationHeaderKeys {
    static let validationMode = "ProxLock_VALIDATION_MODE"
    static let appleTeamID = "ProxLock_APPLE_TEAM_ID"
}

enum DeviceValidationMode: String, Codable, CaseIterable {
    case deviceCheck = "device-check"
    case web = "web"
}
