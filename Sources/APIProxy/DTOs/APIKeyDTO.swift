import Fluent
import Vapor

struct APIKeyRecievingDTO: Content {
    let name: String?
    let apiKey: String?
    let description: String?
}

struct APIKeySendingDTO: Content {
    let id: UUID?
    let name: String
    var userPartialKey: String?
    let description: String
}
