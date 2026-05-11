import Fluent
import Vapor

struct UserDTO: Content {
    var id: String?
    let projects: [ProjectDTO]?
    let currentSubscription: SubscriptionPlans?
    let currentRequestUsage: Int?
    let requestLimit: Int?
    let currentWebSocketUsage: WebSocketUsageDTO?
    let accessKeyLimit: Int?
    let apiKeyLimit: Int?
    let projectLimit: Int?
    var justRegistered: Bool?
    let accessKeys: [UserAPIKeyDTO]?
    let isAdmin: Bool?
    let lastAcceptedTOS: TimeInterval?
}

struct WebSocketUsageDTO: Content {
    let connectionCount: Int64
    let connectionSeconds: Int64
    let connectionSecondLimit: Int64
    let messageCount: Int64
    let messageUnits: Int64
    let messageUnitLimit: Int64
    let bytesClientToUpstream: Int64
    let bytesUpstreamToClient: Int64
}

struct UserAPIKeyDTO: Content {
    let name: String?
    let key: String?
}

struct PaginatedUsersDTO: Content {
    let metadata: PageMetadata
    let users: [UserDTO]
}
