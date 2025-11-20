import Fluent

extension DailyUserUsageHistory: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
    ]
    
    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(DailyUserUsageHistory.schema)
                .id()
                .field("request_count", .int, .required)
                .field("day", .date, .required)
                .field("subscription", .array(of: .string), .required)
                .field("monthly_usage_id", .uuid, .required, .references(MonthlyUserUsageHistory.schema, "id", onDelete: .cascade))
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(MonthlyUserUsageHistory.schema).delete()
        }
    }
}
