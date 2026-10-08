import Vapor

/// Application-local snapshots of dashboard reads. Models and streamed proxy bodies
/// are never retained here. The TTL starts when the response is stored, not on a hit.
actor ReadCache {
    struct Key: Hashable, Sendable {
        let userID: UUID
        let url: String
        let accept: [String]
    }

    struct Snapshot: Sendable {
        let headers: HTTPHeaders
        let body: ByteBuffer

        func response() -> Response {
            Response(status: .ok, headers: headers, body: .init(buffer: body))
        }
    }

    enum Lookup: Sendable {
        case hit(Snapshot)
        case miss(UInt64)
        case bypass
    }

    private struct Entry {
        let snapshot: Snapshot
        let expiresAt: ContinuousClock.Instant
    }

    static let ttl: Duration = .seconds(300)
    static let maximumBodyBytes = 256 * 1024
    private let maximumEntries: Int
    private var entries: [Key: Entry] = [:]
    private var generation: UInt64 = 0
    private var activeWrites = 0

    init(maximumEntries: Int = 256) {
        precondition(maximumEntries > 0)
        self.maximumEntries = maximumEntries
    }

    func lookup(_ key: Key, now: ContinuousClock.Instant = .now) -> Lookup {
        guard activeWrites == 0 else { return .bypass }
        if let entry = entries[key], entry.expiresAt > now {
            return .hit(entry.snapshot)
        }
        entries.removeValue(forKey: key)
        return .miss(generation)
    }

    func store(_ snapshot: Snapshot, for key: Key, generation expectedGeneration: UInt64,
               now: ContinuousClock.Instant = .now) {
        // An earlier read may finish after a write. It must not repopulate stale data.
        guard activeWrites == 0, expectedGeneration == generation,
              snapshot.body.readableBytes <= Self.maximumBodyBytes else { return }
        entries = entries.filter { $0.value.expiresAt > now }
        if entries[key] == nil, entries.count >= maximumEntries,
           let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = Entry(snapshot: snapshot, expiresAt: now.advanced(by: Self.ttl))
    }

    // Invalidate before and after writes, including failed writes that may have
    // persisted partial work. Reads during a write always go to their handler.
    func beginWrite() {
        activeWrites += 1
        invalidate()
    }

    func endWrite() {
        activeWrites -= 1
        invalidate()
    }

    private func invalidate() {
        generation &+= 1
        entries.removeAll(keepingCapacity: true)
    }
}

extension Application {
    private struct ReadCacheStorageKey: StorageKey {
        typealias Value = ReadCache
    }

    var readCache: ReadCache {
        if let cache = storage[ReadCacheStorageKey.self] { return cache }
        let cache = ReadCache()
        storage[ReadCacheStorageKey.self] = cache
        return cache
    }
}
