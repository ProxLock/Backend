import Fluent

extension User: Migratable {
    static let migrations: [any Migration] = [
        CreateUserMigration(),
        UpdateUserToClerkMigration(),
        AddBillToUserMigration(),
        AddOverrideMonthlyRequestLimit()
    ]
    
    struct CreateUserMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.schema)
                .id()
                .field("name", .string, .required)
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(User.schema).delete()
        }
    }
    
    struct UpdateUserToClerkMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.schema)
                .field("clerk_id", .string, .required)
                .deleteField("name")
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(User.schema)
                .deleteField("clerk_id")
                .field("name", .string, .required)
                .update()
        }
    }
    
    struct AddBillToUserMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.schema)
                .field("current_subscription", .string)
                .update()
        }
        
        func revert(on database: any Database) async throws {
            try await database.schema(User.schema)
                .deleteField("current_subscription")
                .update()
        }
    }
    
    struct AddOverrideMonthlyRequestLimit: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.schema)
                .field("override_monthly_request_limit", .int)
                .update()
        }
        
        func revert(on database: any Database) async throws {
            try await database.schema(User.schema)
                .deleteField("override_monthly_request_limit")
                .update()
        }
    }
}
