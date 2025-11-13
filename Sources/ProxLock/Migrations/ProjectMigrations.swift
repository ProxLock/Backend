import Fluent

extension Project: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
        AddDescriptionMigration()
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(Project.schema)
                .id()
                .field("name", .string, .required)
                .field("user_id", .uuid, .required, .references(User.schema, "id"))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(Project.schema).delete()
        }
    }
    
    struct AddDescriptionMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(Project.schema)
                .field("description", .string, .required, .sql(.default("")))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(Project.schema)
                .deleteField("description")
                .update()
        }
    }
}
