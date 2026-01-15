import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
    let currentSubscription: SubscriptionPlans?
    let currentRequestUsage: Int?
    let requestLimit: Int?
    var justRegistered: Bool?
    let apiKeys: [String]?
    let isAdmin: Bool?
}

struct UserAPIKeyDTO: Content {
    let key: String
}

struct PaginatedUsersDTO: Content {
    let metadata: PageMetadata
    let users: [UserDTO]
}
