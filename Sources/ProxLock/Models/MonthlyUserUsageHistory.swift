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
}
