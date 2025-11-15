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
    
        guard let buffer = req.body.data else {
            throw Abort(.internalServerError)
        }
        
        let webhookItem: SubscriptionWebhookItem = try jsonDecoder.decode(SubscriptionWebhookItem.self, from: buffer)
        
        guard let user = try await User.query(on: req.db).filter(\.$clerkID == webhookItem.data.payer.userId).first() else {
            throw Abort(.notFound)
        }
        
        let items = webhookItem.data.items
        
        guard let activeItem = items.first(where: { $0.periodStart < Date() && $0.periodEnd > Date()}) else {
            throw Abort(.internalServerError)
        }
        
        user.currentSubscription = activeItem.plan.slug
        try await user.save(on: req.db)
        
        let currentUsageRecord = try await getOrCreateCurrentHistoricalRecord(req: req, user: user)
        currentUsageRecord.subscription.insert(activeItem.plan.slug)
        
        try await currentUsageRecord.save(on: req.db)
        
        return .noContent
    }
    
    private func getOrCreateCurrentHistoricalRecord(req: Request, user: User) async throws -> UserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await UserUsageHistory.query(on: req.db).filter(\.$month == Date().startOfMonth(calendar: calendar)).filter(\.$user.$id == user.requireID()).with(\.$user).first()
        
        if historyEntry == nil {
            let newEntry = UserUsageHistory(requestCount: 0, subscription: user.currentSubscription ?? .free, month: Date().startOfMonth())
            
            newEntry.$user.id = try user.requireID()
            
            try await newEntry.save(on: req.db)
            
            historyEntry = newEntry
        }
        
        guard let historyEntry else {
            throw Abort(.internalServerError)
        }
        
        return historyEntry
    }
}

// MARK: - Welcome
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
    let planId, status: String
    let updatedAt: Date
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.id = try container.decode(String.self, forKey: .id)
        self.interval = try container.decode(String.self, forKey: .interval)
        self.object = try container.decode(String.self, forKey: .object)
        self.periodEnd = try container.decode(Date.self, forKey: .periodEnd)
        self.periodStart = try container.decode(Date.self, forKey: .periodStart)
        self.plan = try container.decode(Plan.self, forKey: .plan)
        self.planId = try container.decode(String.self, forKey: .planId)
        self.status = try container.decode(String.self, forKey: .status)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    
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
