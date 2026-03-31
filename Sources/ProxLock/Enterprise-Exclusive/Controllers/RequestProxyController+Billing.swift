//
//  RequestProxyController+Billing.swift
//  ProxLock
//
//  Created by Morris Richman on 3/4/26.
//

import Vapor

extension RequestProxyController {
    func validateUserLimitAllowsRequest(req: Request, dbKey: APIKey, with user: User) async throws -> Bool {
        // Limit of less than or equal to -1 is Infinite
        if let overrideMonthlyRequestLimit = user.overrideMonthlyRequestLimit, overrideMonthlyRequestLimit <= -1 {
            return true
        }
        
        let currentRecord = try await Cache.shared.getOrCreateMonthlyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        
        return currentRecord.requestCount < user.monthlyRequestLimit
    }
    
    func addToUsersRequestHistory(req: Request, dbKey: APIKey, with user: User) async throws {
        // Get Historical Log
        let monthlyEntry = try await Cache.shared.getOrCreateMonthlyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        
        // Update Entry
        monthlyEntry.requestCount += 1
        try await monthlyEntry.save(on: req.db)
        
        let dailyEntry = try await Cache.shared.getOrCreateDailyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        dailyEntry.requestCount += 1
        try await dailyEntry.save(on: req.db)
    }
}
