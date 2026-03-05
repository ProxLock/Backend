//
//  User+Billing.swift
//  ProxLock
//
//  Created by Morris Richman on 3/4/26.
//

import Vapor
import Fluent

extension User {
    func getOrCreateCurrentMonthlyHistoricalRecord(req: Request) async throws -> MonthlyUserUsageHistory {
        try await getOrCreateCurrentMonthlyHistoricalRecord(db: req.db)
    }
    
    func getOrCreateCurrentMonthlyHistoricalRecord(db: any Database) async throws -> MonthlyUserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await MonthlyUserUsageHistory.query(on: db).filter(\.$month == Date().startOfMonth(calendar: calendar)).filter(\.$user.$id == requireID()).with(\.$user).first()
        
        if historyEntry == nil {
            let newEntry = MonthlyUserUsageHistory(requestCount: 0, subscription: currentSubscription ?? .free, month: Date().startOfMonth(calendar: calendar))
            
            newEntry.$user.id = try requireID()
            
            try await newEntry.save(on: db)
            
            historyEntry = newEntry
        }
        
        guard let historyEntry else {
            throw Abort(.internalServerError)
        }
        
        return historyEntry
    }
}
