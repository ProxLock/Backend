import Fluent
import Vapor

struct PlayIntegrityConfigLinkRecievingDTO: Content {
    let projectID: UUID
}

struct PlayIntegrityConfigSendingDTO: Content {
    let bypassToken: String
    let clientEmail: String
}
