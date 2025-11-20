import Fluent

extension MonthlyUserUsageHistory: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(MonthlyUserUsageHistory.schema)
                .id()
                .field("request_count", .int, .required)
                .field("month", .date, .required)
                .field("subscription", .array(of: .string), .required)
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(MonthlyUserUsageHistory.schema).delete()
        }
    }
}
