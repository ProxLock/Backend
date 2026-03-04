import Fluent
import Vapor
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class DailyUserUsageHistory: Model, @unchecked Sendable {
    static let schema = "daily_user_usage_histories"
    
    @ID
    var id: UUID?
    
    @Field(key: "request_count")
    var requestCount: Int
    
    @Field(key: "day")
    var day: Date
    
    @Field(key: "subscription")
    var subscription: Set<SubscriptionPlans>
    
    @Parent(key: "monthly_usage_id")
    var monthlyUsage: MonthlyUserUsageHistory

    init() {}
    
    init(id: UUID? = nil, requestCount: Int, subscription: SubscriptionPlans, day: Date) {
        self.id = id
        self.requestCount = requestCount
        self.subscription = [subscription]
        self.day = day
    }
    
    func toDTO() throws -> DailyUserUsageHistoryDTO {
        return .init(id: try requireID(), requestCount: requestCount, subscription: subscription, day: day)
    }
}
