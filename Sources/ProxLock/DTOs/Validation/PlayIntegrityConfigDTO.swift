import Fluent
import Vapor
@preconcurrency import Core

struct PlayIntegrityConfigRecievingDTO: Content {
    let packageName: String
    let gcloudJson: GoogleServiceAccountCredentials
}

struct PlayIntegrityConfigLinkRecievingDTO: Content {
    let projectID: UUID
}

struct PlayIntegrityConfigSendingDTO: Content {
    let packageName: String
    let bypassToken: String
    let clientEmail: String
    let projectID: UUID
}
