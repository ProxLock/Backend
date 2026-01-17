import Fluent

extension User.AccessKey: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
        AddNameMigration()
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.AccessKey.schema)
                .field("id", .string, .required)
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .unique(on: .id)
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(User.AccessKey.schema).delete()
        }
    }
    
    struct AddNameMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.AccessKey.schema)
                .field("name", .string, .required)
                .update()
        }
        
        func revert(on database: any Database) async throws {
            try await database.schema(User.AccessKey.schema)
                .deleteField("name")
                .update()
        }
    }
}
