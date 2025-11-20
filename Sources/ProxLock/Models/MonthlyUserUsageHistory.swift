import Fluent
import Vapor
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class MonthlyUserUsageHistory: Model, @unchecked Sendable {
    static let schema = "user_usage_histories"
    
    @ID
    var id: UUID?
    
    @Field(key: "request_count")
    var requestCount: Int
    
    @Field(key: "month")
    var month: Date
    
    @Field(key: "subscription")
    var subscription: Set<SubscriptionPlans>
    
    @Children(for: \.$monthlyUsage)
    var dailyUsage: [DailyUserUsageHistory]
    
    @Parent(key: "user_id")
    var user: User

    init() {}
    
    init(id: UUID? = nil, requestCount: Int, subscription: SubscriptionPlans, month: Date) {
        self.id = id
        self.requestCount = requestCount
        self.subscription = [subscription]
        self.month = month
    }
    
    func toDTO() throws -> MonthlyUserUsageHistoryDTO {
        return .init(id: try requireID(), requestCount: requestCount, subscription: subscription, month: month)
    }
    
    func getOrCreateCurrentDailyHistoricalRecord(req: Request) async throws -> DailyUserUsageHistory {
        try await getOrCreateCurrentDailyHistoricalRecord(db: req.db)
    }
    
    func getOrCreateCurrentDailyHistoricalRecord(db: any Database) async throws -> DailyUserUsageHistory {
        // Get Historical Log
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .gmt
        
        var historyEntry = try await DailyUserUsageHistory.query(on: db).filter(\.$day == Date().startOfDay(calendar: calendar)).filter(\.$user.$id == requireID()).with(\.$user).first()
        
        if historyEntry == nil {
            try await $user.load(on: db)
            let user = try await $user.get(on: db)
            
            let newEntry = DailyUserUsageHistory(requestCount: 0, subscription: user.currentSubscription ?? .free, day: Date().startOfDay(calendar: calendar))
            
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
