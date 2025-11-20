import Fluent
import Vapor

struct MonthlyUserUsageHistoryDTO: Content {
    let id: UUID
    let requestCount: Int
    let subscription: Set<SubscriptionPlans>
    let month: Date
}

struct DailyUserUsageHistoryDTO: Content {
    let id: UUID
    let requestCount: Int
    let subscription: Set<SubscriptionPlans>
    let day: Date
}
