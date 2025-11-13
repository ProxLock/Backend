import Fluent

extension APIKey: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
        AddDescriptionMigration()
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .id()
                .field("name", .string, .required)
                .field("partial_key", .string, .required)
                .field("project_id", .uuid, .required, .references(Project.schema, "id"))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema).delete()
        }
    }
    
    struct AddDescriptionMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("description", .string, .required, .sql(.default("")))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("description")
                .update()
        }
    }
}
