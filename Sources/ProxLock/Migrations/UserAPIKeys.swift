import Fluent

extension User.APIKey: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.APIKey.schema)
                .field("id", .string, .required)
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .unique(on: .id)
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(User.APIKey.schema).delete()
        }
    }
    
    struct AddNameMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.APIKey.schema)
                .field("name", .string)
                .update()
        }
        
        func revert(on database: any Database) async throws {
            try await database.schema(User.APIKey.schema)
                .deleteField("name")
                .update()
        }
    }
}
