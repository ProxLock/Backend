//
//  User+Billing.swift
//  ProxLock
//
//  Created by Morris Richman on 3/4/26.
//

import Vapor
import Fluent

extension User {
    var monthlyWebSocketConnectionSecondLimit: Int64 {
        webSocketLimit(
            override: overrideMonthlyWebSocketConnectionSecondLimit,
            planLimit: (currentSubscription ?? .free).webSocketConnectionSecondLimit
        )
    }

    var monthlyWebSocketMessageUnitLimit: Int64 {
        webSocketLimit(
            override: overrideMonthlyWebSocketMessageUnitLimit,
            planLimit: (currentSubscription ?? .free).webSocketMessageUnitLimit
        )
    }

    private func webSocketLimit(override: Int64?, planLimit: Int64) -> Int64 {
        guard let override else {
            return planLimit
        }

        guard override >= 0 else {
            return override
        }

        return max(override, planLimit)
    }

    func currentWebSocketUsageDTO(on db: any Database) async throws -> WebSocketUsageDTO {
        let totals = try await currentWebSocketUsageTotals(on: db)

        return WebSocketUsageDTO(
            connectionCount: totals.connectionCount,
            connectionSeconds: totals.connectionSeconds,
            connectionSecondLimit: monthlyWebSocketConnectionSecondLimit,
            messageCount: totals.messageCount,
            messageUnits: totals.messageUnits,
            messageUnitLimit: monthlyWebSocketMessageUnitLimit,
            bytesClientToUpstream: totals.bytesClientToUpstream,
            bytesUpstreamToClient: totals.bytesUpstreamToClient
        )
    }

    func currentWebSocketUsageTotals(on db: any Database, date: Date = .now) async throws -> WebSocketUsageTotals {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        let billingMonth = date.startOfMonth(calendar: calendar)
        let userID = try requireID()

        func monthlyQuery() -> QueryBuilder<WebSocketUsageSession> {
            WebSocketUsageSession.query(on: db)
                .filter(\.$user.$id == userID)
                .filter(\.$billingMonth == billingMonth)
        }

        return WebSocketUsageTotals(
            connectionCount: Int64(try await monthlyQuery().count()),
            connectionSeconds: try await monthlyQuery().sum(\.$connectionSeconds) ?? 0,
            messageCount: try await monthlyQuery().sum(\.$messageCount) ?? 0,
            messageUnits: try await monthlyQuery().sum(\.$messageUnits) ?? 0,
            bytesClientToUpstream: try await monthlyQuery().sum(\.$bytesClientToUpstream) ?? 0,
            bytesUpstreamToClient: try await monthlyQuery().sum(\.$bytesUpstreamToClient) ?? 0
        )
    }

    /// Gets the current month's historical record or creates it if necessary.
    ///
    /// - Warning: This method does not use the cache.
    func getOrCreateMonthlyHistoricalRecord(_ date: Date, req: Request) async throws -> MonthlyUserUsageHistory {
        try await getOrCreateMonthlyHistoricalRecord(date, db: req.db)
    }
    
    /// Gets the current month's historical record or creates it if necessary.
    ///
    /// - Warning: This method does not use the cache.
    func getOrCreateMonthlyHistoricalRecord(_ date: Date, db: any Database) async throws -> MonthlyUserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await MonthlyUserUsageHistory.query(on: db).filter(\.$month == date.startOfMonth(calendar: calendar)).filter(\.$user.$id == requireID()).with(\.$user).first()
        
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
