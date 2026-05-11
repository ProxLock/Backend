//
//  Contants.swift
//  ProxLock
//
//  Created by Morris Richman on 1/11/26.
//

import Vapor

struct Constants {
    static let adminClerkIDs: Set<String> = Set(Environment.get("CLERK_ADMIN_IDS")?.components(separatedBy: ", ") ?? [])
    static let clerkWebhookSecret: String = Environment.get("CLERK_WEBHOOK_SECRET")!
    static let dbHostname = Environment.get("DATABASE_HOST") ?? "localhost"
    static let blacklistedProxyDestinations: Set<String> = Set([dbHostname] + (Environment.get("BLACKLISTED_PROXY_DESTINATIONS")?.components(separatedBy: ", ") ?? []))
    static let termsLastUpdated = Date(timeIntervalSince1970: TimeInterval(Environment.get("TERMS_LAST_UPDATED") ?? "") ?? 1767225600)
    static let minimumTermsDateForProxy = Date(timeIntervalSince1970: TimeInterval(Environment.get("MINIMUM_TERMS_DATE_FOR_PROXY") ?? "") ?? 1767225600)
    /// Maximum single WebSocket frame accepted by the proxy and upstream WebSocket client.
    static let proxyWebSocketMaxFrameSizeBytes = max(
        1,
        Environment.get("PROXY_WEBSOCKET_MAX_FRAME_SIZE_BYTES").flatMap(Int.init) ?? 20 * 1024 * 1024
    )
    /// Configuration values above this threshold are allowed, but logged at startup for operator visibility.
    static let proxyWebSocketHighFrameSizeWarningThresholdBytes = 50 * 1024 * 1024
    /// Maximum pending writes the proxy will queue in either direction before closing the socket pair.
    static let proxyWebSocketMaxBufferedBytesPerDirection = max(
        proxyWebSocketMaxFrameSizeBytes,
        Environment.get("PROXY_WEBSOCKET_MAX_BUFFERED_BYTES_PER_DIRECTION").flatMap(Int.init) ?? proxyWebSocketMaxFrameSizeBytes * 2
    )
    /// Limits fragmented upstream messages so many small fragments cannot aggregate without bound.
    static let proxyWebSocketMaxAccumulatedFrameCount = max(
        1,
        Environment.get("PROXY_WEBSOCKET_MAX_ACCUMULATED_FRAME_COUNT").flatMap(Int.init) ?? 4096
    )
}
