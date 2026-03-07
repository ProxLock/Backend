//
//  Cache.swift
//  ProxLock
//
//  Created by Morris Richman on 3/7/26.
//

import Vapor
import Fluent
import Queues

struct CacheValue<T> : Sendable where T: Sendable {
    let value: T
    let expiry: Date
}

/// Cleans Up Cache
struct CacheCleanupJob: AsyncScheduledJob {
    private let cache = Cache.shared

    func run(context: QueueContext) async throws {
        for item in await cache.apiKeys.filter({ $0.value.expiry < Date() }) {
            await cache.removeAPIKey(item.key)
        }
        for item in await cache.projects.filter({ $0.value.expiry < Date() }) {
            await cache.removeProject(item.key)
        }
        for item in await cache.users.filter({ $0.value.expiry < Date() }) {
            await cache.removeUser(item.key)
        }
        for item in await cache.clerkIDUsers.filter({ $0.value.expiry < Date() }) {
            guard let id = item.value.value.id else { continue }
            await cache.removeUser(id)
        }
        for item in await cache.monthlyUserUsage.filter({ $0.value.expiry < Date() }) {
            await cache.removeMonthlyUserUsage(for: item.key)
        }
        for item in await cache.dailyUserUsage.filter({ $0.value.expiry < Date() }) {
            await cache.removeDailyUserUsage(for: item.key)
        }
    }
}

extension Cache {
    fileprivate func removeAPIKey(_ id: APIKey.IDValue) async {
        self.apiKeys.removeValue(forKey: id)
    }
    
    fileprivate func removeProject(_ id: Project.IDValue) async {
        self.projects.removeValue(forKey: id)
    }
    
    fileprivate func removeUser(_ id: User.IDValue) async {
        self.users.removeValue(forKey: id)
        self.clerkIDUsers.removeValue(forKey: "\(id)")
    }
}

/// A cache of various objects that holds for 1 hour after initial fetch
actor Cache {
    static let shared = Cache()
    
    fileprivate var apiKeys: [APIKey.IDValue: CacheValue<APIKey>] = [:]
    fileprivate var projects: [Project.IDValue: CacheValue<Project>] = [:]
    fileprivate var users: [User.IDValue: CacheValue<User>] = [:]
    fileprivate var clerkIDUsers: [String: CacheValue<User>] = [:]
    internal var monthlyUserUsage: [CacheUsageLookup: CacheValue<MonthlyUserUsageHistory>] = [:]
    internal var dailyUserUsage: [CacheUsageLookup: CacheValue<DailyUserUsageHistory>] = [:]
    
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
    internal func generateExpiration() -> Date {
        .now.addingTimeInterval(60*60)
    }
}

extension APIKey {
    func delete(on db: any Database) async throws {
        try await Cache.shared.removeAPIKey(self.requireID())
        try await self.delete(force: false, on: db)
    }
}

extension Project {
    func delete(on db: any Database) async throws {
        try await Cache.shared.removeProject(self.requireID())
        try await self.delete(force: false, on: db)
    }
}

extension User {
    func delete(on db: any Database) async throws {
        try await Cache.shared.removeUser(self.requireID())
        try await self.delete(force: false, on: db)
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
