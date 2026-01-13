import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
    let currentSubscription: SubscriptionPlans?
    let currentRequestUsage: Int?
    let requestLimit: Int?
    var justRegistered: Bool?
    let isAdmin: Bool?
}

struct PaginatedUsersDTO: Content {
    let metadata: PageMetadata
    let users: [UserDTO]
}
