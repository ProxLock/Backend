import Fluent

extension WebSocketUsageSession: Migratable {
    static let migrations: [any Migration] = [
        CreateMigration(),
    ]

    struct CreateMigration: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(WebSocketUsageSession.schema)
                .id()
                .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
                .field("api_key_id", .uuid, .required, .references(APIKey.schema, "id", onDelete: .cascade))
                .field("destination_host", .string, .required)
                .field("billing_month", .date, .required)
                .field("started_at", .datetime, .required)
                .field("closed_at", .datetime)
                .field("connection_seconds", .int64, .required)
                .field("message_count", .int64, .required)
                .field("message_units", .int64, .required)
                .field("bytes_client_to_upstream", .int64, .required)
                .field("bytes_upstream_to_client", .int64, .required)
                .create()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(WebSocketUsageSession.schema).delete()
        }
    }
}
