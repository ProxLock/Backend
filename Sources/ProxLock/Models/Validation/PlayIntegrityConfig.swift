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

    @Field(key: "package_name")
    var packageName: String

    @Field(key: "bypass_token")
    var bypassToken: String

    @Parent(key: "project_id")
    var project: Project
    
    @Children(for: \.$playIntegrityConfig)
    private var apiKeys: [APIKey]
    
    var configData: GoogleServiceAccountCredentials {
        get throws {
            try GoogleServiceAccountCredentials(fromJsonString: gcloudJson)
        }
    }
    
    init() { }

    init(id: UUID? = nil, packageName: String, gcloudJson: String, bypassToken: String = UUID().uuidString) {
        self.id = id
        self.packageName = packageName
        self.gcloudJson = gcloudJson
        self.bypassToken = bypassToken
    }
    
    func toDTO() throws -> PlayIntegrityConfigSendingDTO {
        let json = try GoogleServiceAccountCredentials(fromJsonString: gcloudJson)
        
        return .init(packageName: packageName, bypassToken: bypassToken, clientEmail: json.clientEmail, projectID: $project.id)
    }
}
