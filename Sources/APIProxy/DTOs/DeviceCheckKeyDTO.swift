import Fluent
import Vapor

struct DeviceCheckKeyRecievingDTO: Content {
    let teamID: String
    let keyID: String
    let privateKey: String?
}

struct DeviceCheckKeySendingDTO: Content {
    let teamID: String
    let keyID: String
    let bypassToken: String
}
