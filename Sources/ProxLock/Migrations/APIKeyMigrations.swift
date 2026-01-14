import Fluent

extension APIKey: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
        AddDescriptionMigration(),
        AddWhitelistedUrls(),
        AddRateLimit(),
        AddAllowsWeb(),
        AddDirectLinkToUser(),
        AddDirectLinkToDeviceValidation()
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
    
    struct AddWhitelistedUrls: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("whitelisted_urls", .array(of: .string))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("whitelisted_urls")
                .update()
        }
    }
    
    struct AddRateLimit: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("rate_limit", .int)
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("rate_limit")
                .update()
        }
    }
    
    struct AddAllowsWeb: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("allows_web", .bool, .required, .sql(.default(false)))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("allows_web")
                .update()
        }
    }
    
    struct AddDirectLinkToUser: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("user_id", .uuid, .references(User.schema, "id", onDelete: .cascade))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("user_id")
                .update()
        }
    }
    
    struct AddDirectLinkToDeviceValidation: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .field("device_check_id", .uuid, .references(DeviceCheckKey.schema, "id"))
                .field("play_integrity_id", .uuid, .references(PlayIntegrityConfig.schema, "id"))
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(APIKey.schema)
                .deleteField("device_check_id")
                .deleteField("play_integrity_id")
                .update()
        }
    }
}
