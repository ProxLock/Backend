import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
    let currentSubscription: SubscriptionPlans?
    let currentRequestUsage: Int?
    let requestLimit: Int?
    let accessKeyLimit: Int?
    let apiKeyLimit: Int?
    let projectLimit: Int?
    var justRegistered: Bool?
    let accessKeys: [UserAPIKeyDTO]?
    let isAdmin: Bool?
}

struct UserAPIKeyDTO: Content {
    let id: String?
    let name: String?
    var key: String?
    let displayPrefix: String?
}

struct PaginatedUsersDTO: Content {
    let metadata: PageMetadata
    let users: [UserDTO]
}
