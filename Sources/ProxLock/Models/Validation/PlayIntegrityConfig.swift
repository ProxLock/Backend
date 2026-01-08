import Fluent
import Vapor
import Core
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class PlayIntegrityConfig: Model, @unchecked Sendable {
    static let schema = "play_integrity_configs"
    
    @ID
    var id: UUID?

    @Field(key: "gcloud_json")
    var gcloudJson: String

    @Field(key: "bypass_token")
    var bypassToken: String

    @Parent(key: "project_id")
    var project: Project
    
    init() { }

    init(id: UUID? = nil, gcloudJson: String, bypassToken: String = UUID().uuidString) {
        self.id = id
        self.gcloudJson = gcloudJson
        self.bypassToken = bypassToken
    }
    
    func toDTO() throws -> PlayIntegrityConfigSendingDTO {
        guard let jsonData = gcloudJson.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to serialize Google Cloud JSON")
        }
        let json = try JSONDecoder().decode(GoogleServiceAccountCredentials.self, from: jsonData)
        
        return .init(bypassToken: bypassToken, clientEmail: json.clientEmail)
    }
}
