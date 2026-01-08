import Fluent

extension PlayIntegrityConfig: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema)
                .id()
                .field("gcloud_json", .string, .required)
                .field("bypass_token", .string, .required)
                .field("project_id", .uuid, .required, .references(Project.schema, "id", onDelete: .cascade))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema).delete()
        }
    }
}
