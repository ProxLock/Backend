import Fluent
import Vapor

struct UserUsageHistoryDTO: Content {
    let id: UUID
    let requestCount: Int
    let subscription: Set<SubscriptionPlans>
    let month: Date
}
