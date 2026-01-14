//
//  DataLinkingMigrationController.swift
//  ProxLock
//
//  Created by Morris Richman on 1/14/26.
//

import Foundation
import Vapor
import Fluent

actor APIKeyDataLinkingMigrationController {
    /// The IDs of ``APIKey`` objects that are currently being updated.
    private var activelyLinkingUser: [UUID] = []
    /// The IDs of ``APIKey`` objects that are currently being updated.
    private var activelyLinkingDeviceCheck: [UUID] = []
    /// The IDs of ``APIKey`` objects that are currently being updated.
    private var activelyLinkingPlayIntegrity: [UUID] = []
    
    func getUser(forAPIKey dbKey: APIKey, on req: Request) async throws -> User {
        if dbKey.$user.id == nil {
            // Get Project
            try await dbKey.$project.load(on: req.db)
            let project = try await dbKey.$project.get(on: req.db)
            
            // Get User
            try await project.$user.load(on: req.db)
            let user = try await project.$user.get(on: req.db)
            
            if try !activelyLinkingUser.contains(dbKey.requireID()) {
                activelyLinkingUser.append(try dbKey.requireID())
                dbKey.$user.id = try user.requireID()
                try await dbKey.save(on: req.db)
                activelyLinkingUser.removeAll { (try? $0 == dbKey.requireID()) ?? false }
            }
            
            return user
        } else {
            try await dbKey.$user.load(on: req.db)
            guard let user = try await dbKey.$user.get(on: req.db) else {
                throw Abort(.internalServerError, reason: "Could not load User from APIKey")
            }
            
            return user
        }
    }
    
    func getDeviceCheckKey(for dbKey: APIKey, from request: Request) async throws -> DeviceCheckKey {
        if dbKey.$deviceCheckKey.id == nil {
            try await dbKey.$project.load(on: request.db)
            let project = try await dbKey.$project.get(on: request.db)
            
            try await project.$deviceCheckKey.load(on: request.db)
            guard let key = try await project.$deviceCheckKey.get(on: request.db) else {
                throw Abort(.unauthorized, reason: "Key was not found")
            }
            
            if try !activelyLinkingDeviceCheck.contains(dbKey.requireID()) {
                activelyLinkingDeviceCheck.append(try dbKey.requireID())
                // Set direct link
                dbKey.$deviceCheckKey.id = try key.requireID()
                try await dbKey.save(on: request.db)
                activelyLinkingDeviceCheck.removeAll { (try? $0 == dbKey.requireID()) ?? false }
            }
            
            return key
        } else {
            try await dbKey.$deviceCheckKey.load(on: request.db)
            guard let key = try await dbKey.$deviceCheckKey.get(on: request.db) else {
                throw Abort(.unauthorized, reason: "Key was not found")
            }
            
            return key
        }
    }
    
    func getPlayIntegrityConfig(for dbKey: APIKey, from request: Request) async throws -> PlayIntegrityConfig {
        if dbKey.$playIntegrityConfig.id == nil {
            try await dbKey.$project.load(on: request.db)
            let project = try await dbKey.$project.get(on: request.db)
            
            try await project.$playIntegrityConfig.load(on: request.db)
            guard let integrityConfig = try await project.$playIntegrityConfig.get(on: request.db) else {
                throw Abort(.internalServerError, reason: "Play Integrity Config was not found")
            }
            
            if try !activelyLinkingPlayIntegrity.contains(dbKey.requireID()) {
                activelyLinkingPlayIntegrity.append(try dbKey.requireID())
                // Set direct link
                dbKey.$playIntegrityConfig.id = try integrityConfig.requireID()
                try await dbKey.save(on: request.db)
                activelyLinkingPlayIntegrity.removeAll { (try? $0 == dbKey.requireID()) ?? false }
            }
            
            return integrityConfig
        } else {
            try await dbKey.$playIntegrityConfig.load(on: request.db)
            guard let integrityConfig = try await dbKey.$playIntegrityConfig.get(on: request.db) else {
                throw Abort(.internalServerError, reason: "Play Integrity Config was not found")
            }
            
            return integrityConfig
        }
    }
}
