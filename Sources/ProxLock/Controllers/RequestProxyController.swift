import Fluent
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
import NIOWebSocket
import Vapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestProxyController: RouteCollection {
    let apiKeyDataLinkingMigrationController: APIKeyDataLinkingMigrationController
    
    func boot(routes: any RoutesBuilder) throws {
        let keys = routes.grouped("proxy")

        keys.post(use: proxyRequest)
        keys.get("ws", use: proxyWebSocketRequest)
    }

    /// POST /proxy
    /// 
    /// Proxies a request to an external service using a split API key for secure authentication.
    /// 
    /// ## Required Headers
    /// - ProxLock_ASSOCIATION_ID: The API key ID for authentication
    /// - ProxLock_HTTP_METHOD: The HTTP method for the target request
    /// - ProxLock_DESTINATION: The destination URL for the proxied request
    /// - `ProxLock_VALIDATION_MODE`: The mode for validating the request (device-check, web)
    ///
    /// ## Partial Key Usage
    /// Include your partial key in any header by wrapping it like: `%ProxLock_PARTIAL_KEY:<your_partial_key>%`
    /// This will be replaced with the complete key before forwarding to the target service.
    /// 
    /// ## Request Body
    /// The request body will be forwarded as-is to the target service. Include any data that the target API expects.
    /// 
    /// - Parameters:
    ///   - req: The HTTP request containing the proxy headers and request body
    /// - Returns: ``Response`` streamed from the target service
    @Sendable
    func proxyRequest(req: Request) async throws -> Response {
        let preparedProxyRequest = try await prepareProxyRequest(req: req, mode: .http)

        var request = HTTPClientRequest(url: preparedProxyRequest.destinationString)
        request.method = .RAW(value: preparedProxyRequest.httpMethod)
        request.headers = preparedProxyRequest.headers
        if let body = req.body.data {
            request.body = .bytes(body)
        }

        Task {
            do {
                try await addToUsersHttpRequestHistory(req: req, dbKey: preparedProxyRequest.dbKey, with: preparedProxyRequest.user)
            } catch {
                req.logger.error("Error Adding to Request History: \(error)")
            }
        }

        let upstreamResponse = try await req.application.http.client.shared.execute(
            request,
            deadline: .distantFuture,
            logger: req.logger
        )
        var responseHeaders = upstreamResponse.headers
        removeHopByHopHeaders(from: &responseHeaders)

        return Response(
            status: upstreamResponse.status,
            headers: responseHeaders,
            body: .init(managedAsyncStream: { writer in
                for try await chunk in upstreamResponse.body {
                    try await writer.write(.buffer(chunk))
                }
            })
        )
    }

    /// Validates `/proxy/ws` and returns the WebSocket upgrade response for an authorized proxy request.
    ///
    /// Proxy validation intentionally happens before the `101 Switching Protocols` response so clients
    /// receive normal HTTP handshake errors instead of ProxLock frames inside their application protocol.
    @Sendable
    func proxyWebSocketRequest(req: Request) async throws -> Response {
        let preparedProxyRequest = try await prepareProxyRequest(req: req, mode: .webSocket)
        var selectedUpgradeHeaders = HTTPHeaders()
        if let subprotocol = selectedWebSocketSubprotocol(from: req.headers) {
            selectedUpgradeHeaders.replaceOrAdd(name: "Sec-WebSocket-Protocol", value: subprotocol)
        }
        let upgradeHeaders = selectedUpgradeHeaders

        let response = Response(status: .switchingProtocols)
        response.upgrader = ConfigurableWebSocketUpgrader(
            maxFrameSize: Constants.proxyWebSocketMaxFrameSizeBytes,
            maxAccumulatedFrameSize: Constants.proxyWebSocketMaxFrameSizeBytes,
            maxAccumulatedFrameCount: Constants.proxyWebSocketMaxAccumulatedFrameCount,
            shouldUpgrade: {
                req.eventLoop.makeSucceededFuture(upgradeHeaders)
            },
            onUpgrade: { clientWebSocket in
                Task {
                    await proxyWebSocket(req: req, preparedProxyRequest: preparedProxyRequest, clientWebSocket: clientWebSocket)
                }
            }
        )
        return response
    }

    /// Proxies an accepted `/proxy/ws` WebSocket connection to the configured upstream WebSocket destination.
    @Sendable
    private func proxyWebSocket(req: Request, preparedProxyRequest: PreparedProxyRequest, clientWebSocket: WebSocket) async {
        do {
            var upstreamHeaders = preparedProxyRequest.headers
            removeWebSocketHandshakeHeaders(from: &upstreamHeaders)

            var upstreamConfiguration = WebSocketClient.Configuration(maxFrameSize: Constants.proxyWebSocketMaxFrameSizeBytes)
            upstreamConfiguration.maxAccumulatedFrameSize = Constants.proxyWebSocketMaxFrameSizeBytes
            upstreamConfiguration.maxAccumulatedFrameCount = Constants.proxyWebSocketMaxAccumulatedFrameCount

            try await WebSocket.connect(
                to: preparedProxyRequest.destinationURL,
                headers: upstreamHeaders,
                configuration: upstreamConfiguration,
                on: req.eventLoop
            ) { upstreamWebSocket in
                let destinationHost = preparedProxyRequest.destinationURL.host() ?? "unknown"
                let trafficMeter = ProxyWebSocketTrafficMeter(
                    apiKeyID: preparedProxyRequest.apiKeyID,
                    destinationHost: destinationHost,
                    maxBufferedBytesPerDirection: Constants.proxyWebSocketMaxBufferedBytesPerDirection
                )
                let billingState = ProxyWebSocketBillingState()

                bridgeWebSockets(
                    clientWebSocket: clientWebSocket,
                    upstreamWebSocket: upstreamWebSocket,
                    trafficMeter: trafficMeter,
                    billingState: billingState,
                    req: req,
                    user: preparedProxyRequest.user,
                    logger: req.logger
                )

                createWebSocketUsageSession(
                    req: req,
                    dbKey: preparedProxyRequest.dbKey,
                    user: preparedProxyRequest.user,
                    destinationHost: destinationHost
                ).whenComplete { result in
                    upstreamWebSocket.eventLoop.execute {
                        do {
                            let usageSession = try result.get()
                            let usageSessionID = try usageSession.requireID()
                            let usageFlushTask = startWebSocketUsageFlushLoop(
                                req: req,
                                user: preparedProxyRequest.user,
                                sessionID: usageSessionID,
                                trafficMeter: trafficMeter,
                                clientWebSocket: clientWebSocket,
                                upstreamWebSocket: upstreamWebSocket,
                                logger: req.logger
                            )
                            Task {
                                await billingState.activate(sessionID: usageSessionID, usageFlushTask: usageFlushTask)
                            }
                        } catch {
                            req.logger.error("WebSocket billing session failed: \(error)")
                            closeWebSocketPair(clientWebSocket, upstreamWebSocket)
                        }
                    }
                }
            }.get()
        } catch {
            req.logger.error("WebSocket proxy failed: \(error)")
            closeWebSocket(clientWebSocket)
        }
    }

    private enum ProxyMode {
        case http
        case webSocket
    }

    /// Normalized proxy request state shared by the HTTP and WebSocket forwarding paths.
    private struct PreparedProxyRequest {
        let destinationString: String
        let destinationURL: URL
        let httpMethod: String
        let headers: HTTPHeaders
        let dbKey: APIKey
        let apiKeyID: UUID
        let user: User
    }

    /// Validates proxy headers, enforces destination/user policy, and reconstructs whitelisted secret headers.
    private func prepareProxyRequest(req: Request, mode: ProxyMode) async throws -> PreparedProxyRequest {
        var headers = req.headers
        guard let associationIdString = headers.first(name: ProxyHeaderKeys.associationId) else {
            throw Abort(.badRequest, reason: ProxyError.associationIdMissing.localizedDescription)
        }
        guard let associationId = UUID(uuidString: associationIdString) else {
            throw Abort(.badRequest, reason: "Unexpected error parsing association ID from request headers.")
        }

        guard let partialKey = headers.first(where: { $0.value.contains(ProxyHeaderKeys.partialKeyIdentifier)}) else {
            throw Abort(.badRequest, reason: ProxyError.partialKeyMissing.localizedDescription)
        }

        let httpMethod: String
        switch mode {
        case .http:
            guard let requestedHTTPMethod = headers.first(name: ProxyHeaderKeys.httpMethod) else {
                throw Abort(.badRequest, reason: ProxyError.httpMethodMissing.localizedDescription)
            }
            httpMethod = requestedHTTPMethod
        case .webSocket:
            httpMethod = "GET"
        }

        guard let destinationString = headers.first(name: ProxyHeaderKeys.destination), let destinationURL = URL(string: destinationString) else {
            throw Abort(.badRequest, reason: ProxyError.destinationMissing.localizedDescription)
        }

        if mode == .webSocket {
            guard ["ws", "wss"].contains(destinationURL.scheme?.lowercased()) else {
                throw Abort(.badRequest, reason: "WebSocket proxy destinations must use ws:// or wss://")
            }
        }

        guard let destinationHost = destinationURL.host(),
                !Constants.blacklistedProxyDestinations.contains(destinationHost),
              !Constants.blacklistedProxyDestinations.contains(destinationString.removingProxyScheme)
        else {
            throw Abort(.forbidden, reason: "Proxying to this destination is not permitted")
        }

        headers.remove(name: ProxyHeaderKeys.destination)
        headers.remove(name: ProxyHeaderKeys.httpMethod)
        headers.remove(name: ProxyHeaderKeys.associationId)
        headers.remove(name: "X-Apple-Device-Token")
        headers.remove(name: "Host")

        // Get Full Key
        guard let dbKey = try await Cache.shared.getAPIKey(associationId, on: req.db) else {
            throw Abort(.badRequest, reason: "Key was not found")
        }

        guard !(dbKey.whitelistedUrls ?? []).isEmpty else {
            throw Abort(.forbidden, reason: "No destinations have been whitelisted for this API key. Please configure whitelisted destinations in your API key settings.")
        }

        guard !(dbKey.whitelistedHeaders ?? []).isEmpty else {
            throw Abort(.forbidden, reason: "No headers have been whitelisted for this API key. Please configure whitelisted headers in your API key settings.")
        }

        // Get User
        let user = try await apiKeyDataLinkingMigrationController.getUser(forAPIKey: dbKey, on: req)

        guard let lastAcceptedTOS = user.lastAcceptedTOS, lastAcceptedTOS >= Constants.minimumTermsDateForProxy else {
            throw Abort(.forbidden, headers: .init([("Code", "-1")]), reason: "The developer must accept the ProxLock Terms of Service to use this API. Please do so at https://app.proxlock.dev")
        }

        switch mode {
        case .http:
            guard try await validateHttpUserLimitAllowsRequest(req: req, dbKey: dbKey, with: user) else {
                throw Abort(.paymentRequired, reason: "Beyond request limit")
            }
        case .webSocket:
            guard try await validateUserAllowsWebSocketStart(req: req, dbKey: dbKey, with: user) else {
                throw Abort(.paymentRequired, reason: "Beyond WebSocket usage limit")
            }
        }

        let checkingUrls = (dbKey.whitelistedUrls ?? []).filter { getHostFromString($0) == destinationURL.host }

        // Ensure the url is allowed
        guard destinationURL.host != nil, !checkingUrls.isEmpty else {
            throw Abort(.forbidden)
        }

        for whitelistedUrl in checkingUrls {
            // Wildcard path protections
            guard let path = getPathFromString(whitelistedUrl), (destinationURL.path().hasPrefix("\(path)/") || destinationURL.path().hasSuffix(path)) else {
                guard whitelistedUrl != checkingUrls.last else {
                    throw Abort(.forbidden)
                }

                continue
            }

            break
        }

        guard let userPartialKeyRange = partialKey.value.range(of: #"(?<=%ProxLock_PARTIAL_KEY:).+(?=.$)"#, options: .regularExpression) else {
            throw Abort(.badRequest, reason: "Partial Key was not found")
        }
        let userPartialKey = String(partialKey.value[userPartialKeyRange])
        let completeKey = try KeySplitter.reconstruct(serverShareB64: dbKey.partialKey, clientShareB64: userPartialKey)
        for header in headers where ((dbKey.whitelistedHeaders ?? []).map({ $0.lowercased() }).contains(header.name.lowercased()) && header.value.contains(ProxyHeaderKeys.partialKeyIdentifier)) {
            headers.replaceOrAdd(name: header.name, value: header.value.replacingOccurrences(of: "\(ProxyHeaderKeys.partialKeyIdentifier)\(userPartialKey)%", with: completeKey))
        }
        removeHopByHopHeaders(from: &headers)

        return PreparedProxyRequest(
            destinationString: destinationString,
            destinationURL: destinationURL,
            httpMethod: httpMethod,
            headers: headers,
            dbKey: dbKey,
            apiKeyID: try dbKey.requireID(),
            user: user
        )
    }

    /// Installs bidirectional frame handlers between the client socket and upstream socket.
    private func bridgeWebSockets(
        clientWebSocket: WebSocket,
        upstreamWebSocket: WebSocket,
        trafficMeter: ProxyWebSocketTrafficMeter,
        billingState: ProxyWebSocketBillingState,
        req: Request,
        user: User,
        logger: Logger
    ) {
        let clientToUpstreamForwarder = NIOLoopBound(
            ProxyWebSocketForwarder(
                direction: .clientToUpstream,
                destinationWebSocket: upstreamWebSocket,
                peerWebSocket: clientWebSocket,
                trafficMeter: trafficMeter,
                logger: logger
            ),
            eventLoop: upstreamWebSocket.eventLoop
        )
        let upstreamToClientForwarder = NIOLoopBound(
            ProxyWebSocketForwarder(
                direction: .upstreamToClient,
                destinationWebSocket: clientWebSocket,
                peerWebSocket: upstreamWebSocket,
                trafficMeter: trafficMeter,
                logger: logger
            ),
            eventLoop: clientWebSocket.eventLoop
        )

        clientWebSocket.onText { _, text in
            upstreamWebSocket.eventLoop.execute {
                clientToUpstreamForwarder.value.enqueueTextOnEventLoop(text)
            }
        }

        clientWebSocket.onBinary { _, buffer in
            upstreamWebSocket.eventLoop.execute {
                clientToUpstreamForwarder.value.enqueueBinaryOnEventLoop(buffer)
            }
        }

        upstreamWebSocket.onText { _, text in
            clientWebSocket.eventLoop.execute {
                upstreamToClientForwarder.value.enqueueTextOnEventLoop(text)
            }
        }

        upstreamWebSocket.onBinary { _, buffer in
            clientWebSocket.eventLoop.execute {
                upstreamToClientForwarder.value.enqueueBinaryOnEventLoop(buffer)
            }
        }

        clientWebSocket.onClose.whenComplete { _ in
            closeWebSocket(upstreamWebSocket)
            Task {
                await finishWebSocketConnection(
                    trafficMeter,
                    billingState: billingState,
                    req: req,
                    user: user,
                    logger: logger
                )
            }
        }

        upstreamWebSocket.onClose.whenComplete { _ in
            closeWebSocket(clientWebSocket)
            Task {
                await finishWebSocketConnection(
                    trafficMeter,
                    billingState: billingState,
                    req: req,
                    user: user,
                    logger: logger
                )
            }
        }
    }

    /// Starts periodic durable billing flushes for an accepted WebSocket connection.
    private func startWebSocketUsageFlushLoop(
        req: Request,
        user: User,
        sessionID: WebSocketUsageSession.IDValue,
        trafficMeter: ProxyWebSocketTrafficMeter,
        clientWebSocket: WebSocket,
        upstreamWebSocket: WebSocket,
        logger: Logger
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }

                let delta = await trafficMeter.usageDelta()
                do {
                    try await flushWebSocketUsageSnapshot(req: req, sessionID: sessionID, delta: delta)
                    if try await currentWebSocketUsageExceedsActiveGrace(req: req, user: user) {
                        logger.warning("WebSocket usage exceeded active connection grace; closing connection")
                        closeWebSocketPair(clientWebSocket, upstreamWebSocket)
                        return
                    }
                } catch {
                    logger.error("Error flushing WebSocket usage: \(error)")
                }
            }
        }
    }

    /// Logs a single close summary for a proxied WebSocket connection.
    private func finishWebSocketConnection(
        _ trafficMeter: ProxyWebSocketTrafficMeter,
        billingState: ProxyWebSocketBillingState,
        req: Request,
        user: User,
        logger: Logger
    ) async {
        let billingSnapshot = await billingState.finish()
        billingSnapshot.usageFlushTask?.cancel()
        await billingSnapshot.usageFlushTask?.value

        guard let snapshot = await trafficMeter.finish() else {
            return
        }

        if let usageSessionID = billingSnapshot.sessionID {
            do {
                try await closeWebSocketUsageSession(req: req, sessionID: usageSessionID, delta: snapshot.usageDelta)
                if try await currentWebSocketUsageExceedsActiveGrace(req: req, user: user) {
                    logger.warning("WebSocket usage exceeded active connection grace after final flush")
                }
            } catch {
                logger.error("Error closing WebSocket usage session: \(error)")
            }
        } else if !snapshot.usageDelta.isEmpty {
            logger.warning("WebSocket closed before billing session was created; final usage could not be saved")
        }

        logger.info("WebSocket proxy connection closed", metadata: [
            "apiKeyID": .string(snapshot.apiKeyID.uuidString),
            "destinationHost": .string(snapshot.destinationHost),
            "durationSeconds": .stringConvertible(snapshot.durationSeconds),
            "clientToUpstreamBytes": .stringConvertible(snapshot.clientToUpstreamBytes),
            "upstreamToClientBytes": .stringConvertible(snapshot.upstreamToClientBytes),
            "clientToUpstreamMessages": .stringConvertible(snapshot.clientToUpstreamMessages),
            "upstreamToClientMessages": .stringConvertible(snapshot.upstreamToClientMessages),
            "messageUnits": .stringConvertible(snapshot.messageUnits)
        ])
    }

    /// Closes both sides of a proxied WebSocket pair after a write failure or local buffer-limit breach.
    private func closeWebSocketPair(_ first: WebSocket, _ second: WebSocket) {
        closeProxyWebSocketPair(first, second)
    }

    private func closeWebSocket(_ webSocket: WebSocket) {
        closeProxyWebSocket(webSocket)
    }
    
    private func getHostFromString(_ string: String) -> String? {
        URL(string: "http://\(string.removingProxyScheme)")?.host()
    }
    
    private func getPathFromString(_ string: String) -> String? {
        URL(string: "http://\(string.removingProxyScheme)")?.path()
    }
    
    private func removeHopByHopHeaders(from headers: inout HTTPHeaders) {
        let connectionHeaderNames = headers
            .filter { $0.name.lowercased() == "connection" }
            .flatMap { header in
                header.value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        
        for headerName in connectionHeaderNames {
            headers.remove(name: headerName)
        }
        
        for headerName in [
            "Connection",
            "Keep-Alive",
            "Proxy-Connection",
            "Proxy-Authenticate",
            "Proxy-Authorization",
            "TE",
            "Trailer",
            "Transfer-Encoding",
            "Upgrade"
        ] {
            headers.remove(name: headerName)
        }
    }

    private func removeWebSocketHandshakeHeaders(from headers: inout HTTPHeaders) {
        for headerName in [
            "Sec-WebSocket-Accept",
            "Sec-WebSocket-Extensions",
            "Sec-WebSocket-Key",
            "Sec-WebSocket-Version"
        ] {
            headers.remove(name: headerName)
        }
    }

    private func selectedWebSocketSubprotocol(from headers: HTTPHeaders) -> String? {
        headers.first(name: "Sec-WebSocket-Protocol")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

}

/// WebSocket upgrader that exposes WebSocketKit aggregation limits Vapor's convenience helper does not.
private struct ConfigurableWebSocketUpgrader: Upgrader {
    let maxFrameSize: Int
    let maxAccumulatedFrameSize: Int
    let maxAccumulatedFrameCount: Int
    let shouldUpgrade: @Sendable () -> EventLoopFuture<HTTPHeaders?>
    let onUpgrade: @Sendable (WebSocket) -> Void

    func applyUpgrade(req: Request, res: Response) -> any HTTPServerProtocolUpgrader {
        NIOWebSocketServerUpgrader(
            maxFrameSize: maxFrameSize,
            automaticErrorHandling: false,
            shouldUpgrade: { _, _ in
                shouldUpgrade()
            },
            upgradePipelineHandler: { channel, _ in
                var configuration = WebSocket.Configuration()
                configuration.maxAccumulatedFrameSize = maxAccumulatedFrameSize
                configuration.maxAccumulatedFrameCount = maxAccumulatedFrameCount
                return WebSocket.server(on: channel, config: configuration, onUpgrade: onUpgrade)
            }
        )
    }
}

/// Direction label used for per-direction WebSocket byte and message accounting.
private enum ProxyWebSocketDirection {
    case clientToUpstream
    case upstreamToClient
}

private func closeProxyWebSocketPair(_ first: WebSocket, _ second: WebSocket) {
    closeProxyWebSocket(first)
    closeProxyWebSocket(second)
}

private func closeProxyWebSocket(_ webSocket: WebSocket) {
    let eventLoop = webSocket.eventLoop
    if eventLoop.inEventLoop {
        webSocket.close(promise: nil)
    } else {
        eventLoop.execute {
            webSocket.close(promise: nil)
        }
    }
}

/// Event-loop-bound ordered sender for one direction of a proxied WebSocket pair.
///
/// Mutable state in this class is only accessed on `destinationWebSocket.eventLoop`.
private final class ProxyWebSocketForwarder {
    private enum Message {
        case text(String)
        case binary(ByteBuffer)

        var byteCount: Int {
            switch self {
            case .text(let text):
                return text.utf8.count
            case .binary(let buffer):
                return buffer.readableBytes
            }
        }
    }

    private let direction: ProxyWebSocketDirection
    private let destinationWebSocket: WebSocket
    private let peerWebSocket: WebSocket
    private let trafficMeter: ProxyWebSocketTrafficMeter
    private let logger: Logger
    private var queue: [Message] = []
    private var isSending = false
    private var isClosed = false

    init(
        direction: ProxyWebSocketDirection,
        destinationWebSocket: WebSocket,
        peerWebSocket: WebSocket,
        trafficMeter: ProxyWebSocketTrafficMeter,
        logger: Logger
    ) {
        self.direction = direction
        self.destinationWebSocket = destinationWebSocket
        self.peerWebSocket = peerWebSocket
        self.trafficMeter = trafficMeter
        self.logger = logger
    }

    func enqueueTextOnEventLoop(_ text: String) {
        enqueueOnEventLoop(.text(text))
    }

    func enqueueBinaryOnEventLoop(_ buffer: ByteBuffer) {
        enqueueOnEventLoop(.binary(buffer))
    }

    private func enqueueOnEventLoop(_ message: Message) {
        destinationWebSocket.eventLoop.preconditionInEventLoop()
        guard !isClosed else {
            return
        }

        queue.append(message)
        drainOnEventLoop()
    }

    private func drainOnEventLoop() {
        destinationWebSocket.eventLoop.preconditionInEventLoop()
        guard !isClosed, !isSending, let message = queue.first else {
            return
        }

        isSending = true
        let byteCount = message.byteCount
        let direction = self.direction
        let eventLoop = destinationWebSocket.eventLoop
        let trafficMeter = self.trafficMeter
        let loopBoundForwarder = NIOLoopBound(self, eventLoop: eventLoop)

        Task {
            let reserved = await trafficMeter.reserveOutgoingBytes(byteCount, direction: direction)
            eventLoop.execute {
                loopBoundForwarder.value.sendReservedMessageOnEventLoop(message, byteCount: byteCount, reserved: reserved)
            }
        }
    }

    private func sendReservedMessageOnEventLoop(_ message: Message, byteCount: Int, reserved: Bool) {
        destinationWebSocket.eventLoop.preconditionInEventLoop()
        guard !isClosed else {
            isSending = false
            return
        }

        guard reserved else {
            isClosed = true
            closeProxyWebSocketPair(destinationWebSocket, peerWebSocket)
            return
        }

        let promise = destinationWebSocket.eventLoop.makePromise(of: Void.self)
        switch message {
        case .text(let text):
            destinationWebSocket.send(text, promise: promise)
        case .binary(let buffer):
            destinationWebSocket.send(buffer, promise: promise)
        }

        let direction = self.direction
        let eventLoop = destinationWebSocket.eventLoop
        let trafficMeter = self.trafficMeter
        let loopBoundForwarder = NIOLoopBound(self, eventLoop: eventLoop)

        promise.futureResult.whenComplete { result in
            Task {
                await trafficMeter.completeOutgoingBytes(byteCount, direction: direction)
                eventLoop.execute {
                    loopBoundForwarder.value.completeSendOnEventLoop(result)
                }
            }
        }
    }

    private func completeSendOnEventLoop(_ result: Result<Void, any Error>) {
        destinationWebSocket.eventLoop.preconditionInEventLoop()
        if !queue.isEmpty {
            queue.removeFirst()
        }
        isSending = false

        if case .failure(let error) = result {
            logger.error("WebSocket proxy send failed: \(error)")
            isClosed = true
            closeProxyWebSocketPair(destinationWebSocket, peerWebSocket)
            return
        }

        drainOnEventLoop()
    }
}

private actor ProxyWebSocketBillingState {
    struct Snapshot {
        let sessionID: WebSocketUsageSession.IDValue?
        let usageFlushTask: Task<Void, Never>?
    }

    private var sessionID: WebSocketUsageSession.IDValue?
    private var usageFlushTask: Task<Void, Never>?
    private var isFinished = false

    func activate(sessionID: WebSocketUsageSession.IDValue, usageFlushTask: Task<Void, Never>) {
        guard !isFinished else {
            usageFlushTask.cancel()
            return
        }

        self.sessionID = sessionID
        self.usageFlushTask = usageFlushTask
    }

    func finish() -> Snapshot {
        guard !isFinished else {
            return Snapshot(sessionID: nil, usageFlushTask: nil)
        }

        isFinished = true
        return Snapshot(sessionID: sessionID, usageFlushTask: usageFlushTask)
    }
}

/// Actor-isolated traffic accounting for one proxied WebSocket connection.
///
/// It tracks pending outbound bytes for local buffer protection and records final byte/message totals
/// for close-time logging.
private actor ProxyWebSocketTrafficMeter {
    /// Immutable summary emitted once when either side of the socket pair closes.
    struct Snapshot {
        let apiKeyID: UUID
        let destinationHost: String
        let durationSeconds: Double
        let clientToUpstreamBytes: Int64
        let upstreamToClientBytes: Int64
        let clientToUpstreamMessages: Int64
        let upstreamToClientMessages: Int64
        let messageUnits: Int64
        let usageDelta: WebSocketUsageDelta
    }

    private let startedAt = Date()
    private let maxBufferedBytesPerDirection: Int
    let apiKeyID: UUID
    let destinationHost: String

    private var isFinished = false
    private var pendingClientToUpstreamBytes = 0
    private var pendingUpstreamToClientBytes = 0
    private var clientToUpstreamBytes: Int64 = 0
    private var upstreamToClientBytes: Int64 = 0
    private var clientToUpstreamMessages: Int64 = 0
    private var upstreamToClientMessages: Int64 = 0
    private var messageUnits: Int64 = 0
    private var flushedConnectionSeconds: Int64 = 0
    private var flushedClientToUpstreamBytes: Int64 = 0
    private var flushedUpstreamToClientBytes: Int64 = 0
    private var flushedMessageCount: Int64 = 0
    private var flushedMessageUnits: Int64 = 0

    init(apiKeyID: UUID, destinationHost: String, maxBufferedBytesPerDirection: Int) {
        self.apiKeyID = apiKeyID
        self.destinationHost = destinationHost
        self.maxBufferedBytesPerDirection = maxBufferedBytesPerDirection
    }

    /// Reserves pending outbound capacity and records message totals before a frame is written.
    func reserveOutgoingBytes(_ byteCount: Int, direction: ProxyWebSocketDirection) -> Bool {
        let billableMessageUnits = WebSocketBillingPolicy.messageUnits(for: byteCount)

        switch direction {
        case .clientToUpstream:
            guard pendingClientToUpstreamBytes + byteCount <= maxBufferedBytesPerDirection else {
                return false
            }
            pendingClientToUpstreamBytes += byteCount
            clientToUpstreamBytes += Int64(byteCount)
            clientToUpstreamMessages += 1
        case .upstreamToClient:
            guard pendingUpstreamToClientBytes + byteCount <= maxBufferedBytesPerDirection else {
                return false
            }
            pendingUpstreamToClientBytes += byteCount
            upstreamToClientBytes += Int64(byteCount)
            upstreamToClientMessages += 1
        }

        messageUnits += billableMessageUnits
        return true
    }

    /// Releases pending outbound capacity after the corresponding write promise completes.
    func completeOutgoingBytes(_ byteCount: Int, direction: ProxyWebSocketDirection) {
        switch direction {
        case .clientToUpstream:
            pendingClientToUpstreamBytes = max(0, pendingClientToUpstreamBytes - byteCount)
        case .upstreamToClient:
            pendingUpstreamToClientBytes = max(0, pendingUpstreamToClientBytes - byteCount)
        }
    }

    /// Returns usage accumulated since the previous durable billing flush.
    func usageDelta() -> WebSocketUsageDelta {
        let currentConnectionSeconds = max(Int64(Date().timeIntervalSince(startedAt)), 0)
        let currentMessageCount = clientToUpstreamMessages + upstreamToClientMessages

        let delta = WebSocketUsageDelta(
            connectionSeconds: max(0, currentConnectionSeconds - flushedConnectionSeconds),
            messageCount: max(0, currentMessageCount - flushedMessageCount),
            messageUnits: max(0, messageUnits - flushedMessageUnits),
            bytesClientToUpstream: max(0, clientToUpstreamBytes - flushedClientToUpstreamBytes),
            bytesUpstreamToClient: max(0, upstreamToClientBytes - flushedUpstreamToClientBytes)
        )

        flushedConnectionSeconds = currentConnectionSeconds
        flushedMessageCount = currentMessageCount
        flushedMessageUnits = messageUnits
        flushedClientToUpstreamBytes = clientToUpstreamBytes
        flushedUpstreamToClientBytes = upstreamToClientBytes

        return delta
    }

    /// Returns the final connection snapshot exactly once.
    func finish() -> Snapshot? {
        guard !isFinished else {
            return nil
        }
        isFinished = true
        let finalUsageDelta = usageDelta()

        return Snapshot(
            apiKeyID: apiKeyID,
            destinationHost: destinationHost,
            durationSeconds: Date().timeIntervalSince(startedAt),
            clientToUpstreamBytes: clientToUpstreamBytes,
            upstreamToClientBytes: upstreamToClientBytes,
            clientToUpstreamMessages: clientToUpstreamMessages,
            upstreamToClientMessages: upstreamToClientMessages,
            messageUnits: messageUnits,
            usageDelta: finalUsageDelta
        )
    }
}

private extension String {
    var removingProxyScheme: String {
        replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
    }
}

struct ProxyHeaderKeys {
    static let associationId = "ProxLock_ASSOCIATION_ID"
    static let httpMethod = "ProxLock_HTTP_METHOD"
    static let destination = "ProxLock_DESTINATION"
    static let partialKeyIdentifier = "%ProxLock_PARTIAL_KEY:"
}

private enum ProxyError: Error {
    case associationIdMissing, partialKeyMissing, httpMethodMissing, destinationMissing
    
    var localizedDescription: String {
        switch self {
        case .associationIdMissing: return "Association ID missing from request."
        case .partialKeyMissing: return "Partial key missing from request."
        case .httpMethodMissing: return "HTTP method missing from request."
        case .destinationMissing: return "Destination missing from request."
        }
    }
}
