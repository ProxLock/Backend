//
//  RequestProxyController+Billing.swift
//  ProxLock
//
//  Created by Morris Richman on 3/4/26.
//

import Vapor

extension RequestProxyController {
    func validateHttpUserLimitAllowsRequest(req: Request, dbKey: APIKey, with user: User) async throws -> Bool {
        // Limit of less than or equal to -1 is Infinite
        if let overrideMonthlyRequestLimit = user.overrideMonthlyRequestLimit, overrideMonthlyRequestLimit <= -1 {
            return true
        }
        
        let currentRecord = try await Cache.shared.getOrCreateMonthlyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        
        return currentRecord.requestCount < user.monthlyRequestLimit
    }
    
    func addToUsersHttpRequestHistory(req: Request, dbKey: APIKey, with user: User) async throws {
        // Get Historical Log
        let monthlyEntry = try await Cache.shared.getOrCreateMonthlyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        
        // Update Entry
        monthlyEntry.requestCount += 1
        try await monthlyEntry.save(on: req.db)
        
        let dailyEntry = try await Cache.shared.getOrCreateDailyUserUsageHistory(.now, userID: user.requireID(), on: req.db)
        dailyEntry.requestCount += 1
        try await dailyEntry.save(on: req.db)
    }

    func validateUserAllowsWebSocketStart(req: Request, dbKey: APIKey, with user: User) async throws -> Bool {
        let totals = try await user.currentWebSocketUsageTotals(on: req.db)
        return WebSocketBillingPolicy.allowsNewConnection(usage: totals.connectionSeconds, limit: user.monthlyWebSocketConnectionSecondLimit) &&
            WebSocketBillingPolicy.allowsNewConnection(usage: totals.messageUnits, limit: user.monthlyWebSocketMessageUnitLimit)
    }

    func createWebSocketUsageSession(
        req: Request,
        dbKey: APIKey,
        user: User,
        destinationHost: String
    ) -> EventLoopFuture<WebSocketUsageSession> {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt

        do {
            let session = WebSocketUsageSession(
                userID: try user.requireID(),
                apiKeyID: try dbKey.requireID(),
                destinationHost: destinationHost,
                billingMonth: Date().startOfMonth(calendar: calendar)
            )

            return session.save(on: req.db).map {
                session
            }
        } catch {
            return req.eventLoop.makeFailedFuture(error)
        }
    }

    func flushWebSocketUsageSnapshot(
        req: Request,
        sessionID: WebSocketUsageSession.IDValue,
        delta: WebSocketUsageDelta
    ) async throws {
        guard !delta.isEmpty else {
            return
        }

        guard let session = try await WebSocketUsageSession.find(sessionID, on: req.db) else {
            throw Abort(.notFound, reason: "WebSocket usage session not found")
        }

        apply(delta, to: session)
        try await session.save(on: req.db)
    }

    func closeWebSocketUsageSession(
        req: Request,
        sessionID: WebSocketUsageSession.IDValue,
        delta: WebSocketUsageDelta
    ) async throws {
        guard let session = try await WebSocketUsageSession.find(sessionID, on: req.db) else {
            throw Abort(.notFound, reason: "WebSocket usage session not found")
        }

        apply(delta, to: session)
        session.closedAt = .now
        try await session.save(on: req.db)
    }

    func currentWebSocketUsageExceedsActiveGrace(req: Request, user: User) async throws -> Bool {
        let totals = try await user.currentWebSocketUsageTotals(on: req.db)
        return !WebSocketBillingPolicy.allowsActiveConnection(usage: totals.connectionSeconds, limit: user.monthlyWebSocketConnectionSecondLimit) ||
            !WebSocketBillingPolicy.allowsActiveConnection(usage: totals.messageUnits, limit: user.monthlyWebSocketMessageUnitLimit)
    }

    private func apply(_ delta: WebSocketUsageDelta, to session: WebSocketUsageSession) {
        session.connectionSeconds += delta.connectionSeconds
        session.messageCount += delta.messageCount
        session.messageUnits += delta.messageUnits
        session.bytesClientToUpstream += delta.bytesClientToUpstream
        session.bytesUpstreamToClient += delta.bytesUpstreamToClient
    }

}
