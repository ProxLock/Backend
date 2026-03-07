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
    private var users: [User.IDValue: CacheValue<User>] = [:]
    private var clerkIDUsers: [String: CacheValue<User>] = [:]
    
    /// Gets an ``APIKey`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getAPIKey(_ id: APIKey.IDValue, on db: any Database) async throws -> APIKey? {
        if let item = apiKeys[id], item.expiry > Date() {
            return item.value
        }
        
        // Get Project so we can fetch the user
        guard let item = try await APIKey.find(id, on: db) else {
            apiKeys.removeValue(forKey: id)
            return nil
        }
        
        apiKeys[id] = CacheValue(value: item, expiry: generateExpiration())
        
        return item
    }
    
    /// Gets a ``Project`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getProject(_ id: Project.IDValue, on db: any Database) async throws -> Project? {
        if let item = projects[id], item.expiry > Date() {
            return item.value
        }
        
        // Get Project so we can fetch the user
        guard let item = try await Project.find(id, on: db) else {
            projects.removeValue(forKey: id)
            return nil
        }
        
        projects[id] = CacheValue(value: item, expiry: generateExpiration())
        
        return item
    }
    
    /// Gets a ``User`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getUser(_ id: User.IDValue, on db: any Database) async throws -> User? {
        if let item = users[id], item.expiry > Date() {
            return item.value
        }
        
        // Get Project so we can fetch the user
        guard let item = try await User.find(id, on: db) else {
            users.removeValue(forKey: id)
            return nil
        }
        
        users[id] = CacheValue(value: item, expiry: generateExpiration())
        clerkIDUsers[item.clerkID] = CacheValue(value: item, expiry: generateExpiration())
        
        return item
    }
    
    /// Gets a ``User`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    func getUser(clerkID: String, on db: any Database) async throws -> User? {
        if let item = clerkIDUsers[clerkID], item.expiry > Date() {
            return item.value
        }
        
        // Get Project so we can fetch the user
        guard let item = try await User.query(on: db).filter(\.$clerkID == clerkID).first() else {
            clerkIDUsers.removeValue(forKey: clerkID)
            return nil
        }
        
        clerkIDUsers[clerkID] = CacheValue(value: item, expiry: generateExpiration())
        
        if let userID = item.id {
            users[userID] = CacheValue(value: item, expiry: generateExpiration())
        }
        
        return item
    }
    
    /// Generates an expiration date of 1 hour from now
    private func generateExpiration() -> Date {
        .now.addingTimeInterval(60*60)
    }
}

extension ParentProperty where From == APIKey, To == Project {
    func cachedGet(on db: any Database) async throws -> Project {
        guard let project = try await Cache.shared.getProject(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return project
    }
}

extension ParentProperty where From == Project, To == User {
    func cachedGet(on db: any Database) async throws -> User {
        guard let item = try await Cache.shared.getUser(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return item
    }
}

extension ParentProperty where From == User.AccessKey, To == User {
    func cachedGet(on db: any Database) async throws -> User {
        guard let item = try await Cache.shared.getUser(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return item
    }
}

extension OptionalParentProperty where From == APIKey, To == User {
    func cachedGet(on db: any Database) async throws -> User? {
        guard let id else {
            return nil
        }
        
        guard let item = try await Cache.shared.getUser(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return item
    }
}


extension ParentProperty where From == MonthlyUserUsageHistory, To == User {
    func cachedGet(on db: any Database) async throws -> User {
        guard let item = try await Cache.shared.getUser(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return item
    }
}

extension ParentProperty where From == DailyUserUsageHistory, To == User {
    func cachedGet(on db: any Database) async throws -> User {
        guard let item = try await Cache.shared.getUser(id, on: db) else {
            try await load(on: db)
            return try await get(on: db)
        }
        
        return item
    }
}
