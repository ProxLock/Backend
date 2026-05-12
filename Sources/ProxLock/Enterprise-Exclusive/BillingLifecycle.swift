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
    static func closeWebSocketUsageSessions(_ application: Application) async {
        do {
            let sessions = try await WebSocketUsageSession.query(on: application.db).filter(\.$closedAt == nil).all()
            for session in sessions {
                session.closedAt = Date()
                do {
                    try await session.save(on: application.db)
                } catch {
                    application.logger.error("Failed to save WebSocket Usage Session (\(#file):\(#line)): \(error)")
                }
            }
        } catch {
            application.logger.error("Failed to close WebSocket Usage Sessions (\(#file):\(#line)): \(error)")
        }
    }
}
