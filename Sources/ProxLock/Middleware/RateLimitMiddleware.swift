//
//  RateLimitMiddleware.swift
//  APIProxy
//
//  Created by Morris Richman on 10/10/25.
//

import Foundation
import Vapor
import VaporDeviceCheck
import Fluent
import JWTKit

actor RateLimitManager: Sendable {
    private var trackedLimits: [UUID: (maxLimit: Int, count: Int, lastCreation: Date)] = [:]
    
    func tryRequest(for key: APIKey) async throws {
        guard let trackedLimit = try trackedLimits[key.requireID()] else {
            // Return if no limit
            guard let maxLimit = key.rateLimit else {
                return
            }
            
            // Set if doesn't exist
            try trackedLimits[key.requireID()] = (maxLimit: maxLimit, count: 1, lastCreation: .now)
            return
        }
        
        // Ensure rate limit is reset every 5 minutes
        guard trackedLimit.lastCreation.advanced(by: -60*5) > .now.advanced(by: -60*5) else {
            // Return if no limit
            guard let maxLimit = key.rateLimit else {
                return
            }
            
            try trackedLimits[key.requireID()] = (maxLimit: maxLimit, count: 1, lastCreation: .now)
            return
        }
        
        guard trackedLimit.maxLimit <= trackedLimit.count else {
            throw Abort(.tooManyRequests)
        }
        
        // Increment
        try trackedLimits[key.requireID()]?.count += 1
    }
}

struct RateLimitMiddleware: AsyncMiddleware {
    let manager: RateLimitManager
    
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let associationId = request.headers.first(name: ProxyHeaderKeys.associationId) else {
            throw Abort(.unauthorized, reason: "Failed Device Validation: Association ID not detected")
        }
        
        // Get Project so we can fetch the user
        guard let dbKey = try await APIKey.find(UUID(uuidString: associationId), on: request.db) else {
            throw Abort(.unauthorized, reason: "Key was not found")
        }
        
        try await manager.tryRequest(for: dbKey)
        
        return try await next.respond(to: request)
    }
}
