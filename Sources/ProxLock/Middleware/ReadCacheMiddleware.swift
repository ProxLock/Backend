import Vapor

/// Register after authentication so credentials and TOS are checked on every hit.
struct ReadCacheMiddleware: AsyncMiddleware {
    let cache: ReadCache

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.method == .GET, let userID = request.auth.get(User.self)?.id,
              request.headers[.range].isEmpty,
              request.headers[.ifNoneMatch].isEmpty,
              request.headers[.ifModifiedSince].isEmpty,
              !requiresFreshResponse(request.headers) else {
            return try await next.respond(to: request)
        }

        let key = ReadCache.Key(userID: userID, url: request.url.string, accept: request.headers[.accept])
        let generation: UInt64
        switch await cache.lookup(key) {
        case .hit(let snapshot):
            return snapshot.response()
        case .miss(let value):
            generation = value
        case .bypass:
            return try await next.respond(to: request)
        }

        let response = try await next.respond(to: request)
        // Only buffer successful JSON reads. Never retain cookies, errors, streams,
        // one-time creation secrets, or responses explicitly marked no-store.
        if response.status == .ok, response.headers.contentType == .json,
           response.headers[.setCookie].isEmpty,
           !requiresFreshResponse(response.headers),
           response.headers[.vary].isEmpty,
           response.body.count <= ReadCache.maximumBodyBytes,
           let body = response.body.buffer {
            let snapshot = ReadCache.Snapshot(headers: response.headers, body: body)
            await cache.store(snapshot, for: key, generation: generation)
        }
        return response
    }

    private func requiresFreshResponse(_ headers: HTTPHeaders) -> Bool {
        let directives = headers[.cacheControl].joined(separator: ",").lowercased()
        return directives.contains("no-store") || directives.contains("no-cache")
            || headers[.pragma].joined(separator: ",").lowercased().contains("no-cache")
    }
}

/// Apply to dashboard and webhook mutations, excluding high-volume proxy requests.
struct ReadCacheInvalidationMiddleware: AsyncMiddleware {
    let cache: ReadCache

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard [.POST, .PUT, .PATCH, .DELETE].contains(request.method) else {
            return try await next.respond(to: request)
        }
        await cache.beginWrite()
        do {
            let response = try await next.respond(to: request)
            await cache.endWrite()
            return response
        } catch {
            await cache.endWrite()
            throw error
        }
    }
}
