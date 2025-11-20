//
//  ClerkSubscriptionsWebhook.swift
//  ProxLock
//
//  Created by Morris Richman on 11/14/25.
//

import Vapor
import Fluent

struct ClerkSubscriptionsWebhook: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("subscriptions", use: handleWebhook)
    }
    
    @Sendable
    func handleWebhook(req: Request) async throws -> HTTPStatus {
        guard let svixId = req.headers.first(name: "SVIX-Id"),
              let svixSignature = req.headers.first(name: "SVIX-SIGNATURE"),
              let svixTimestamp = req.headers.first(name: "SVIX-TIMESTAMP"),
              ClerkWebhookManager.isSivxSignatureValid(svixID: svixId, svixTimestamp: svixTimestamp, svixSignature: svixSignature, body: req.body.string ?? "")
        else {
            throw Abort(.unauthorized)
        }
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        jsonDecoder.dateDecodingStrategy = .millisecondsSince1970
        
        let webhookItem: SubscriptionWebhookItem = try req.content.decode(SubscriptionWebhookItem.self, using: jsonDecoder)
        
        guard let user = try await User.query(on: req.db).filter(\.$clerkID == webhookItem.data.payer.userId).first() else {
            throw Abort(.notFound)
        }
        
        let items = webhookItem.data.items
        
        guard let activeItem = items.first(where: { ($0.periodStart < Date() && $0.periodEnd > Date() && $0.status != .ended) || $0.status == .active }) else {
            throw Abort(.internalServerError)
        }
        
        user.currentSubscription = activeItem.plan.slug
        try await user.save(on: req.db)
        
        let currentMonthlyUsageRecord = try await user.getOrCreateCurrentMonthlyHistoricalRecord(req: req)
        currentMonthlyUsageRecord.subscription.insert(activeItem.plan.slug)
        try await currentMonthlyUsageRecord.save(on: req.db)
        
        let currentDailyUsageRecord = try await currentMonthlyUsageRecord.getOrCreateCurrentDailyHistoricalRecord(req: req)
        currentDailyUsageRecord.subscription.insert(activeItem.plan.slug)
        try await currentDailyUsageRecord.save(on: req.db)
        
        return .noContent
    }
}

// MARK: - Top Level Webhook Item
private struct SubscriptionWebhookItem: Codable {
    let data: DataClass
    let instanceId, object: String
    let timestamp: Date
    let type: String
}

// MARK: - DataClass
private struct DataClass: Codable {
    let activeAt: Date
    let createdAt: Date
    let id: String
    let items: [Item]
    let latestPaymentId, object: String
    let payer: Payer
    let payerId, paymentSourceId, status: String
    let updatedAt: Date
}

// MARK: - Item
private struct Item: Codable {
    let createdAt: Date
    let id, interval, object: String
    let periodEnd, periodStart: Date
    let plan: Plan
    let planId: String
    let status: SubscriptionStatus
    let updatedAt: Date
}

// MARK: - Plan
private struct Plan: Codable {
    let amount: Int
    let currency, id: String
    let isRecurring: Bool
    let name: String
    let slug: SubscriptionPlans
}

enum SubscriptionPlans: String, Codable {
    case free = "free_user"
    case tenThousandRequests = "10k_requests"
    case twentyFiveThousandRequests = "25k_requests"
    
    var requestLimit: Int {
        switch self {
        case .free: return 1000
        case .tenThousandRequests: return 10_000
        case .twentyFiveThousandRequests: return 25_000
        }
    }
}

// MARK: - Payer
private struct Payer: Codable {
    let email, firstName, id: String
    let imageUrl: String
    let lastName, organizationId, organizationName, userId: String
}
