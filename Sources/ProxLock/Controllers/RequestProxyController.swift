import Fluent
import AsyncHTTPClient
import NIOCore
import Vapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestProxyController: RouteCollection {
    let apiKeyDataLinkingMigrationController: APIKeyDataLinkingMigrationController
    
    func boot(routes: any RoutesBuilder) throws {
        let keys = routes.grouped("proxy")

        keys.post(use: proxyRequest)
        keys.webSocket("ws", maxFrameSize: WebSocketMaxFrameSize(integerLiteral: Constants.proxyWebSocketMaxFrameSizeBytes)) { req, clientWebSocket async in
            await proxyWebSocket(req: req, clientWebSocket: clientWebSocket)
        }
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
                try await addToUsersRequestHistory(req: req, dbKey: preparedProxyRequest.dbKey, with: preparedProxyRequest.user)
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

    @Sendable
    func proxyWebSocket(req: Request, clientWebSocket: WebSocket) async {
        do {
            let preparedProxyRequest = try await prepareProxyRequest(req: req, mode: .webSocket)

            var upstreamHeaders = preparedProxyRequest.headers
            removeWebSocketHandshakeHeaders(from: &upstreamHeaders)

            try await WebSocket.connect(
                to: preparedProxyRequest.destinationURL,
                headers: upstreamHeaders,
                configuration: .init(maxFrameSize: Constants.proxyWebSocketMaxFrameSizeBytes),
                on: req.eventLoop
            ) { upstreamWebSocket in
                bridgeWebSockets(clientWebSocket: clientWebSocket, upstreamWebSocket: upstreamWebSocket)
            }.get()

            Task {
                do {
                    try await addToUsersRequestHistory(req: req, dbKey: preparedProxyRequest.dbKey, with: preparedProxyRequest.user)
                } catch {
                    req.logger.error("Error Adding to Request History: \(error)")
                }
            }
        } catch {
            req.logger.error("WebSocket proxy failed: \(error)")
            try? await clientWebSocket.close(code: .policyViolation)
        }
    }

    private enum ProxyMode {
        case http
        case webSocket
    }

    private struct PreparedProxyRequest {
        let destinationString: String
        let destinationURL: URL
        let httpMethod: String
        let headers: HTTPHeaders
        let dbKey: APIKey
        let user: User
    }

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

        // Validate user is under request limit
        guard try await validateUserLimitAllowsRequest(req: req, dbKey: dbKey, with: user) else {
            throw Abort(.paymentRequired, reason: "Beyond request limit")
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
            user: user
        )
    }

    private func bridgeWebSockets(clientWebSocket: WebSocket, upstreamWebSocket: WebSocket) {
        clientWebSocket.onText { _, text in
            upstreamWebSocket.send(text)
        }

        clientWebSocket.onBinary { _, buffer in
            upstreamWebSocket.send(buffer)
        }

        upstreamWebSocket.onText { _, text in
            clientWebSocket.send(text)
        }

        upstreamWebSocket.onBinary { _, buffer in
            clientWebSocket.send(buffer)
        }

        clientWebSocket.onClose.whenComplete { _ in
            upstreamWebSocket.close(promise: nil)
        }

        upstreamWebSocket.onClose.whenComplete { _ in
            clientWebSocket.close(promise: nil)
        }
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
