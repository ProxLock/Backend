import Fluent

enum WebSocketBillingUserOverrideMigrations {
    static let migrations: [any Migration] = [
        AddUserWebSocketBillingOverrides(),
    ]

    struct AddUserWebSocketBillingOverrides: AsyncMigration {
        func prepare(on database: any Database) async throws {
            try await database.schema(User.schema)
                .field("override_monthly_websocket_connection_second_limit", .int64)
                .field("override_monthly_websocket_message_unit_limit", .int64)
                .update()
        }

        func revert(on database: any Database) async throws {
            try await database.schema(User.schema)
                .deleteField("override_monthly_websocket_connection_second_limit")
                .deleteField("override_monthly_websocket_message_unit_limit")
                .update()
        }
    }
}
