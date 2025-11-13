import Fluent
import Vapor

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RequestProxyController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let keys = routes.grouped("proxy")

        keys.post(use: proxyRequest)
    }

    /// POST /proxy
    /// 
    /// Proxies a request to an external service using a split API key for secure authentication.
    /// 
    /// ## Required Headers
    /// - ProxLock_ASSOCIATION_ID: The API key ID for authentication
    /// - ProxLock_HTTP_METHOD: The HTTP method for the target request
    /// - ProxLock_DESTINATION: The destination URL for the proxied request
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
    /// - Returns: ``ClientResponse`` from the target service
    @Sendable
    func proxyRequest(req: Request) async throws -> ClientResponse {
        var headers = req.headers
        guard let associationId = headers.first(name: ProxyHeaderKeys.associationId) else { throw ProxyError.associationIdMissing }
        guard let partialKey = headers.first(where: { $0.value.contains(ProxyHeaderKeys.partialKeyIdentifier)}) else { throw ProxyError.partialKeyMissing }
        guard let httpMethod = headers.first(name: ProxyHeaderKeys.httpMethod) else { throw ProxyError.httpMethodMissing }
        guard let destinationString = headers.first(name: ProxyHeaderKeys.destination), let destinationUrl = URL(string: destinationString)
        else { throw ProxyError.destinationMissing }
        
        headers.remove(name: ProxyHeaderKeys.destination)
        headers.remove(name: ProxyHeaderKeys.httpMethod)
        headers.remove(name: ProxyHeaderKeys.associationId)
        headers.remove(name: "X-Apple-Device-Token")
        headers.remove(name: "Host")
        
        // Get Full Key
        guard let dbKey = try await APIKey.find(UUID(uuidString: associationId), on: req.db) else {
            throw Abort(.badRequest, reason: "Key was not found")
        }
        
        let checkingUrls = (dbKey.whitelistedUrls ?? []).filter { getHostFromString($0) == destinationUrl.host }
        
        // Ensure the url is allowed
        guard destinationUrl.host != nil, !checkingUrls.isEmpty else {
            throw Abort(.forbidden)
        }
        
        for whitelistedUrl in checkingUrls {
            // Wildcard path protections
            guard let path = getPathFromString(whitelistedUrl), (destinationUrl.path().hasPrefix("\(path)/") || destinationUrl.path().hasSuffix(path)) else {
                guard whitelistedUrl != checkingUrls.last else {
                    throw Abort(.forbidden)
                }
                
                continue
            }
            
            break
        }
        
        guard let userPartialKeyRange = partialKey.value.range(of: #"(?<=%ProxLock_PARTIAL_KEY:)[^%]+"#, options: .regularExpression) else {
            throw Abort(.badRequest, reason: "Partial Key was not found")
        }
        let userPartialKey = String(partialKey.value[userPartialKeyRange])
        let completeKey = try KeySplitter.reconstruct(serverShareB64: dbKey.partialKey, clientShareB64: userPartialKey)
        for header in headers where header.value.contains(ProxyHeaderKeys.partialKeyIdentifier) {
            headers.replaceOrAdd(name: header.name, value: header.value.replacingOccurrences(of: "\(ProxyHeaderKeys.partialKeyIdentifier)\(userPartialKey)%", with: completeKey))
        }
        
        print("PROXY: Sending Request to \(destinationUrl.host)")
        
        let request = ClientRequest(method: .RAW(value: httpMethod), url: URI(string: destinationString), headers: headers, body: req.body.data)
        return try await req.client.send(request)
    }
    
    private func getHostFromString(_ string: String) -> String? {
        URL(string: "http://\(string.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: ""))")?.host()
    }
    
    private func getPathFromString(_ string: String) -> String? {
        URL(string: "http://\(string.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: ""))")?.path()
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
}
