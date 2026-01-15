import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
    let currentSubscription: SubscriptionPlans?
    let currentRequestUsage: Int?
    let requestLimit: Int?
    let accessKeyLimit: Int?
    var justRegistered: Bool?
    let accessKeys: [UserAPIKeyDTO]?
    let isAdmin: Bool?
}

struct UserAPIKeyDTO: Content {
    let name: String?
    let key: String?
}

struct PaginatedUsersDTO: Content {
    let metadata: PageMetadata
    let users: [UserDTO]
}
