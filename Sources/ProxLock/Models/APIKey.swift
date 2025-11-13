import Fluent
import struct Foundation.UUID

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class APIKey: Model, @unchecked Sendable {
    static let schema = "api_keys"
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String
    
    @Field(key: "description")
    var userDescription: String

    @Field(key: "partial_key")
    var partialKey: String
    
    @Parent(key: "project_id")
    var project: Project

    init() { }

    init(id: UUID? = nil, name: String, description: String, partialKey: String) {
        self.id = id
        self.name = name
        self.userDescription = description
        self.partialKey = partialKey
    }
    
    func toDTO() -> APIKeySendingDTO {
        .init(
            id: self.id,
            name: self.name,
            description: userDescription
        )
    }
}
