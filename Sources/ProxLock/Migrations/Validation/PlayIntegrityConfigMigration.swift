import Fluent

extension PlayIntegrityConfig: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
        AddDeviceValidationModeMigration(),
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema)
                .id()
                .field("gcloud_json", .string, .required)
                .field("bypass_token", .string, .required)
                .field("package_name", .string, .required)
                .field("project_id", .uuid, .required, .references(Project.schema, "id", onDelete: .cascade))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema).delete()
        }
    }
    
    struct AddDeviceValidationModeMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema)
                .field("allowed_app_recognition_verdicts", .array(of: .string))
                .update()
        }
        
        func revert(on database: any Database) async throws {
            try await database.schema(PlayIntegrityConfig.schema)
                .deleteField("allowed_app_recognition_verdicts")
                .update()
        }
    }
}
