import Fluent
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class DeviceCheckKey: Model, @unchecked Sendable {
    static let schema = "device_check_keys"
    
    @ID
    var id: UUID?

    @Field(key: "secret_key")
    var secretKey: String

    @Field(key: "key_id")
    var keyID: String

    @Field(key: "team_id")
    var teamID: String

    @Field(key: "bypass_token")
    var bypassToken: String

    @Parent(key: "project_id")
    var project: Project
    
    @Children(for: \.$deviceCheckKey)
    private var apiKeys: [APIKey]
    
    init() { }

    init(id: UUID? = nil, secretKey: String, keyID: String, teamID: String, bypassToken: String = UUID().uuidString) {
        self.id = id
        self.secretKey = secretKey
        self.keyID = keyID
        self.teamID = teamID
        self.bypassToken = bypassToken
    }
    
    func toDTO() -> DeviceCheckKeySendingDTO {
        .init(teamID: teamID, keyID: keyID, bypassToken: bypassToken)
    }
}
