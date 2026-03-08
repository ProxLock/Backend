//
//  Cache+UsageHistory.swift
//  ProxLock
//
//  Created by Morris Richman on 3/7/26.
//

import Foundation
import Vapor
import Fluent

struct CacheUsageLookup: Sendable, Hashable {
    let date: Date
    let userID: User.IDValue
}

extension Cache {
    private func normalizeMonth(_ date: Date) -> Date {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        return date.startOfMonth(calendar: calendar)
    }
    private func normalizeDay(_ date: Date) -> Date {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        return date.startOfDay(calendar: calendar)
    }
    
    /// Gets/Creates a ``MonthlyUserUsageHistory`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    ///
    /// - Parameters:
    ///   - date: The date for that month. This will automatically be normalized to the beginning of the month.
    ///   - userID: The ID of the ``User`` that you are performing the lookup for.
    ///   - db: The database you might perform the lookup on.
    func getOrCreateMonthlyUserUsageHistory(_ date: Date, userID: User.IDValue, on db: any Database) async throws -> MonthlyUserUsageHistory {
        let date = normalizeMonth(date)
        
        let lookup = CacheUsageLookup(date: date, userID: userID)
        
        if let item = monthlyUserUsage[lookup], item.expiry > Date() {
            return item.value
        }
        
        guard let user = try await getUser(userID, on: db) else {
            monthlyUserUsage.removeValue(forKey: lookup)
            throw Abort(.notFound, reason: "User not found")
        }
        
        // Get Project so we can fetch the user
        let item = try await user.getOrCreateMonthlyHistoricalRecord(date, db: db)
        
        monthlyUserUsage[lookup] = CacheValue(value: item, expiry: generateExpiration())
        
        return item
    }
    
    /// Gets/Creates a ``DailyUserUsageHistory`` from the cache if available, otherwise it pulls it from the database and stores it in the cache for future use.
    ///
    /// - Parameters:
    ///   - date: The date for that day. This will automatically be normalized to the beginning of the day.
    ///   - userID: The ID of the ``User`` that you are performing the lookup for.
    ///   - db: The database you might perform the lookup on.
    func getOrCreateDailyUserUsageHistory(_ date: Date, userID: User.IDValue, on db: any Database) async throws -> DailyUserUsageHistory {
        let date = normalizeDay(date)
        
        let lookup = CacheUsageLookup(date: date, userID: userID)
        
        if let item = dailyUserUsage[lookup], item.expiry > Date() {
            return item.value
        }
        
        let month = try await getOrCreateMonthlyUserUsageHistory(date, userID: userID, on: db)
        
        // Get Project so we can fetch the user
        let item = try await month.getOrCreateDailyHistoricalRecord(date, db: db)
        
        dailyUserUsage[lookup] = CacheValue(value: item, expiry: generateExpiration())
        
        return item
    }
    
    internal func removeMonthlyUserUsage(for key: CacheUsageLookup) {
        monthlyUserUsage.removeValue(forKey: key)
    }
    
    internal func removeDailyUserUsage(for key: CacheUsageLookup) {
        dailyUserUsage.removeValue(forKey: key)
    }
}

extension DailyUserUsageHistory {
    func delete(on db: any Database) async throws {
        try await $monthlyUsage.load(on: db)
        let monthUsage = try await $monthlyUsage.get(on: db)
        
        await Cache.shared.removeDailyUserUsage(for: CacheUsageLookup(date: self.day, userID: monthUsage.$user.id))
        try await self.delete(force: false, on: db)
    }
}

extension MonthlyUserUsageHistory {
    func delete(on db: any Database) async throws {
        await Cache.shared.removeMonthlyUserUsage(for: CacheUsageLookup(date: self.month, userID: $user.id))
        try await self.delete(force: false, on: db)
    }
}
