//
//  BillingLifecycle.swift
//  ProxLock
//
//  Created by Morris Richman on 5/11/26.
//

import Vapor
import Fluent

final class BillingLifecycle {
    /// Marks Websocket Connections as Closed in the Database billing table
    static func closeWebSocketUsageSessions(_ application: Application) async throws {
        let sessions = try await WebSocketUsageSession.query(on: application.db).filter(\.$closedAt == nil).all()
        for session in sessions {
            session.closedAt = Date()
            try await session.save(on: application.db)
        }
    }
}
