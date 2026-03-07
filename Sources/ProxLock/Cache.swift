//
//  Cache.swift
//  ProxLock
//
//  Created by Morris Richman on 3/7/26.
//

import Vapor
import Fluent

struct CacheValue<T> {
    let value: T
    let expiry: Date
}

/// A cache of various objects that holds for 1 hour after initial fetch
actor Cache {
    static let shared = Cache()
    
    private var apiKeys: [APIKey.IDValue: CacheValue<APIKey>] = [:]
    private var projects: [Project.IDValue: CacheValue<Project>] = [:]
    
    /// Gets an ``APIKey`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getAPIKey(_ request: Request, for id: APIKey.IDValue) async throws -> APIKey? {
        if let key = apiKeys[id], key.expiry > Date() {
            return key.value
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await APIKey.find(id, on: request.db) else {
            apiKeys.removeValue(forKey: id)
            return nil
        }
        
        apiKeys[id] = CacheValue(value: dbKey, expiry: generateExpiration())
        
        return dbKey
    }
    
    /// Gets an ``Project`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getProject(_ request: Request, for id: Project.IDValue) async throws -> Project? {
        if let key = projects[id], key.expiry > Date() {
            return key.value
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await Project.find(id, on: request.db) else {
            projects.removeValue(forKey: id)
            return nil
        }
        
        projects[id] = CacheValue(value: dbKey, expiry: generateExpiration())
        
        return dbKey
    }
    
    /// Generates an expiration date of 1 hour from now
    private func generateExpiration() -> Date {
        .now.addingTimeInterval(60*60)
    }
}
