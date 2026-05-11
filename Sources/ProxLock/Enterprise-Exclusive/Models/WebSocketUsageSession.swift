import Fluent
import Vapor
import struct Foundation.UUID

/// A durable billing record for one successfully proxied WebSocket connection.
final class WebSocketUsageSession: Model, @unchecked Sendable {
    static let schema = "websocket_usage_sessions"

    @ID
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "api_key_id")
    var apiKey: APIKey

    @Field(key: "destination_host")
    var destinationHost: String

    @Field(key: "billing_month")
    var billingMonth: Date

    @Field(key: "started_at")
    var startedAt: Date

    @OptionalField(key: "closed_at")
    var closedAt: Date?

    @Field(key: "connection_seconds")
    var connectionSeconds: Int64

    @Field(key: "message_count")
    var messageCount: Int64

    @Field(key: "message_units")
    var messageUnits: Int64

    @Field(key: "bytes_client_to_upstream")
    var bytesClientToUpstream: Int64

    @Field(key: "bytes_upstream_to_client")
    var bytesUpstreamToClient: Int64

    init() {}

    init(
        userID: User.IDValue,
        apiKeyID: APIKey.IDValue,
        destinationHost: String,
        billingMonth: Date,
        startedAt: Date = .now
    ) {
        self.$user.id = userID
        self.$apiKey.id = apiKeyID
        self.destinationHost = destinationHost
        self.billingMonth = billingMonth
        self.startedAt = startedAt
        self.connectionSeconds = 0
        self.messageCount = 0
        self.messageUnits = 0
        self.bytesClientToUpstream = 0
        self.bytesUpstreamToClient = 0
    }
}

/// Customer-facing WebSocket usage totals for one billing month.
struct WebSocketUsageTotals: Sendable {
    var connectionCount: Int64 = 0
    var connectionSeconds: Int64 = 0
    var messageCount: Int64 = 0
    var messageUnits: Int64 = 0
    var bytesClientToUpstream: Int64 = 0
    var bytesUpstreamToClient: Int64 = 0
}

/// Incremental WebSocket usage emitted by the in-memory traffic meter.
struct WebSocketUsageDelta: Sendable {
    var connectionSeconds: Int64
    var messageCount: Int64
    var messageUnits: Int64
    var bytesClientToUpstream: Int64
    var bytesUpstreamToClient: Int64

    var isEmpty: Bool {
        connectionSeconds == 0 &&
        messageCount == 0 &&
        messageUnits == 0 &&
        bytesClientToUpstream == 0 &&
        bytesUpstreamToClient == 0
    }
}

/// Shared billing math for WebSocket usage.
enum WebSocketBillingPolicy {
    static let messageUnitBytes: Int64 = 32 * 1024

    static func messageUnits(for byteCount: Int) -> Int64 {
        let bytes = max(Int64(byteCount), 0)
        return max(1, (bytes + messageUnitBytes - 1) / messageUnitBytes)
    }

    static func allowsNewConnection(usage: Int64, limit: Int64) -> Bool {
        limit <= -1 || usage < limit
    }

    static func allowsActiveConnection(usage: Int64, limit: Int64) -> Bool {
        limit <= -1 || usage <= limit + (limit / 10)
    }
}
