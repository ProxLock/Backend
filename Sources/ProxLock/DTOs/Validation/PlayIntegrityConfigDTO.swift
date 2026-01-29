import Fluent
import Vapor
@preconcurrency import Core

struct PlayIntegrityConfigRecievingDTO: Content {
    let packageName: String?
    let gcloudJson: GoogleServiceAccountCredentials?
    let allowedAppRecognitionVerdicts: [PlayIntegrityResponse.AppIntegrity.Verdict]?
}

struct PlayIntegrityConfigLinkRecievingDTO: Content {
    let projectID: UUID
}

struct PlayIntegrityConfigSendingDTO: Content {
    let packageName: String
    let bypassToken: String
    let clientEmail: String
    let projectID: UUID
    let allowedAppRecognitionVerdicts: [PlayIntegrityResponse.AppIntegrity.Verdict]
}
