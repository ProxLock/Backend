@testable import ProxLock
import Testing
import Vapor
import VaporTesting

struct ReadCacheTests {
    private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func key(_ url: String = "/v1/me") -> ReadCache.Key {
        .init(userID: userID, url: url, accept: [])
    }

    private func snapshot(_ value: String = "{}") -> ReadCache.Snapshot {
        .init(headers: ["Content-Type": "application/json"], body: ByteBuffer(string: value))
    }

    private func isHit(_ lookup: ReadCache.Lookup) -> Bool {
        if case .hit = lookup { return true }
        return false
    }

    @Test func expiresAtFiveMinutesWithoutSlidingOnHits() async {
        let cache = ReadCache()
        let now = ContinuousClock.now
        await cache.store(snapshot(), for: key(), generation: 0, now: now)
        #expect(isHit(await cache.lookup(key(), now: now.advanced(by: .seconds(299)))))
        #expect(!isHit(await cache.lookup(key(), now: now.advanced(by: .seconds(300)))))
    }

    @Test func rejectsReadsOverlappingConcurrentWrites() async {
        let cache = ReadCache()
        await cache.store(snapshot(), for: key(), generation: 0)
        await cache.beginWrite()
        await cache.beginWrite()
        #expect(!isHit(await cache.lookup(key())))
        await cache.endWrite()
        if case .bypass = await cache.lookup(key()) {} else { Issue.record("A write is still active") }
        await cache.endWrite()
        await cache.store(snapshot("stale"), for: key(), generation: 0)
        #expect(!isHit(await cache.lookup(key())))
        if case .miss(let generation) = await cache.lookup(key()) {
            await cache.store(snapshot("fresh"), for: key(), generation: generation)
        }
        #expect(isHit(await cache.lookup(key())))
    }

    @Test func boundsEntriesAndResponseSize() async {
        let cache = ReadCache(maximumEntries: 2)
        let now = ContinuousClock.now
        await cache.store(snapshot(), for: key("/first"), generation: 0, now: now)
        await cache.store(snapshot(), for: key("/second"), generation: 0, now: now.advanced(by: .seconds(1)))
        await cache.store(snapshot(), for: key("/third"), generation: 0, now: now.advanced(by: .seconds(2)))
        #expect(!isHit(await cache.lookup(key("/first"), now: now.advanced(by: .seconds(3)))))
        #expect(isHit(await cache.lookup(key("/second"), now: now.advanced(by: .seconds(3)))))
        await cache.store(snapshot(String(repeating: "x", count: ReadCache.maximumBodyBytes + 1)),
                          for: key("/large"), generation: 0)
        #expect(!isHit(await cache.lookup(key("/large"))))
    }

    @Test func hitsAreIndependentResponseSnapshots() async throws {
        try await withApp { app in
            let cache = ReadCache()
            let handler = CountingResponder()
            let middleware = ReadCacheMiddleware(cache: cache)
            let request = makeRequest(app)
            let first = try await middleware.respond(to: request, chainingTo: handler)
            first.body = .init(string: "changed outside cache")
            let second = try await middleware.respond(to: makeRequest(app), chainingTo: handler)
            #expect(second.body.string == "{\"count\":1}")
            #expect(second.headers.contentType == .json)
            #expect(await handler.count == 1)
        }
    }

    @Test func isolatesUsersQueriesPrefixesAndAcceptHeaders() async throws {
        try await withApp { app in
            let middleware = ReadCacheMiddleware(cache: ReadCache())
            let handler = CountingResponder()
            let first = makeRequest(app)
            _ = try await middleware.respond(to: first, chainingTo: handler)
            let otherUser = makeRequest(app)
            otherUser.auth.login(User(id: UUID(), clerkID: "other"))
            let query = makeRequest(app, url: "/v1/me?page=2")
            let legacy = makeRequest(app, url: "/me")
            let admin = makeRequest(app, url: "/v1/admin/other/user")
            let accept = makeRequest(app)
            accept.headers.add(name: .accept, value: "application/json")
            for request in [otherUser, query, legacy, admin, accept] {
                _ = try await middleware.respond(to: request, chainingTo: handler)
            }
            _ = try await middleware.respond(to: makeRequest(app), chainingTo: handler)
            #expect(await handler.count == 6)
        }
    }

    @Test func neverCachesUnauthenticatedErrorsSecretsOrConditionalReads() async throws {
        try await withApp { app in
            let middleware = ReadCacheMiddleware(cache: ReadCache())
            let unauthenticated = makeRequest(app)
            unauthenticated.auth.logout(User.self)
            let conditional = makeRequest(app)
            conditional.headers.add(name: .ifNoneMatch, value: "test")
            for request in [unauthenticated, conditional, makeRequest(app, method: .POST)] {
                let handler = CountingResponder()
                for _ in 0..<2 { _ = try await middleware.respond(to: request, chainingTo: handler) }
                #expect(await handler.count == 2)
            }
            for headers: HTTPHeaders in [["Set-Cookie": "session=secret"], ["Cache-Control": "no-store"],
                                         ["Cache-Control": "no-cache"], ["Vary": "X-Client"]] {
                let handler = CountingResponder(headers: headers)
                for _ in 0..<2 {
                    _ = try await middleware.respond(to: makeRequest(app), chainingTo: handler)
                }
                #expect(await handler.count == 2)
            }
            let failed = CountingResponder(status: .notFound)
            for _ in 0..<2 { _ = try await middleware.respond(to: makeRequest(app), chainingTo: failed) }
            #expect(await failed.count == 2)
        }
    }

    @Test func freshReadDirectivesBypassExistingHits() async throws {
        try await withApp { app in
            let middleware = ReadCacheMiddleware(cache: ReadCache())
            let handler = CountingResponder()
            _ = try await middleware.respond(to: makeRequest(app), chainingTo: handler)
            for directive in ["no-cache", "no-store"] {
                let request = makeRequest(app)
                request.headers.add(name: .cacheControl, value: directive)
                _ = try await middleware.respond(to: request, chainingTo: handler)
            }
            #expect(await handler.count == 3)
        }
    }

    @Test func dashboardAndWebhookWritesInvalidateEvenOnFailure() async throws {
        try await withApp { app in
            let cache = ReadCache()
            let read = ReadCacheMiddleware(cache: cache)
            let write = ReadCacheInvalidationMiddleware(cache: cache)
            let handler = CountingResponder()
            _ = try await read.respond(to: makeRequest(app), chainingTo: handler)
            _ = try await write.respond(to: makeRequest(app, url: "/me/projects", method: .POST), chainingTo: handler)
            _ = try await read.respond(to: makeRequest(app), chainingTo: handler)
            do {
                _ = try await write.respond(to: makeRequest(app, url: "/webhooks/subscription", method: .POST),
                                            chainingTo: FailingResponder())
                Issue.record("Expected the write to fail")
            } catch {}
            _ = try await read.respond(to: makeRequest(app), chainingTo: handler)
            #expect(await handler.count == 4)
        }
    }

    @Test func authenticationRunsBeforeEveryCachedResponse() async throws {
        try await withApp { app in
            let gate = AuthenticationGate(userID: userID)
            let handler = CountingResponder()
            let authenticated = app.grouped(gate).grouped(ReadCacheMiddleware(cache: app.readCache))
            authenticated.get("me") { request async throws -> Response in
                try await handler.respond(to: request)
            }
            for _ in 0..<2 {
                try await app.testing().test(.GET, "me") { response in
                    #expect(response.status == .ok)
                    #expect(response.body.string == "{\"count\":1}")
                }
            }
            #expect(await gate.authenticationCount == 2)
            #expect(await handler.count == 1)
            await gate.revoke()
            try await app.testing().test(.GET, "me") { response in
                #expect(response.status == .unauthorized)
            }
            #expect(await gate.authenticationCount == 3)
            #expect(await handler.count == 1)
        }
    }

    private func makeRequest(_ app: Application, url: String = "/v1/me", method: HTTPMethod = .GET) -> Request {
        let request = Request(application: app, method: method, url: URI(string: url), on: app.eventLoopGroup.next())
        request.auth.login(User(id: userID, clerkID: "test"))
        return request
    }

    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await test(app)
            try await app.asyncShutdown()
        } catch {
            try await app.asyncShutdown()
            throw error
        }
    }
}

private actor CountingResponder: AsyncResponder {
    private(set) var count = 0
    let status: HTTPStatus
    let headers: HTTPHeaders

    init(status: HTTPStatus = .ok, headers: HTTPHeaders = [:]) {
        self.status = status
        self.headers = headers
    }

    func respond(to request: Request) async throws -> Response {
        count += 1
        let response = Response(status: status, headers: headers, body: .init(string: "{\"count\":\(count)}"))
        response.headers.contentType = .json
        return response
    }
}

private struct FailingResponder: AsyncResponder {
    func respond(to request: Request) async throws -> Response { throw Abort(.internalServerError) }
}

private actor AuthenticationGate: AsyncMiddleware {
    private(set) var authenticationCount = 0
    let userID: UUID
    var allowed = true

    init(userID: UUID) { self.userID = userID }
    func revoke() { allowed = false }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        authenticationCount += 1
        guard allowed else { throw Abort(.unauthorized) }
        request.auth.login(User(id: userID, clerkID: "test"))
        return try await next.respond(to: request)
    }
}
