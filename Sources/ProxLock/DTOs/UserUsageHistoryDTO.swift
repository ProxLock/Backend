import Fluent
import Vapor

struct UserUsageHistoryDTO: Content {
    let id: UUID
    let requestCount: Int
    let subscription: String
    let month: Date
}
