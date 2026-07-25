//
//  HNClient.swift
//  HackerNews
//
//  Thin async wrapper around the Hacker News Firebase API.
//

import Foundation

/// In-memory, time-limited cache for fetched items. Comment threads can be
/// large, so caching keeps re-opening a story (or pulling to refresh moments
/// apart) from re-fetching every node. The TTL is deliberately short so the
/// thread stays close to live.
actor ItemCache {
    static let shared = ItemCache()

    /// How long a cached item is considered fresh.
    static let ttl: TimeInterval = 60

    /// Entries expire lazily on lookup, which never happens for a comment the
    /// user doesn't come back to. Past this many entries we sweep the stale ones
    /// so an afternoon of browsing big threads doesn't retain every comment seen.
    private static let sweepThreshold = 5_000

    private var entries: [Int: (item: HNItem, storedAt: Date)] = [:]

    func cached(_ id: Int) -> HNItem? {
        guard let entry = entries[id] else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < Self.ttl else {
            entries[id] = nil
            return nil
        }
        return entry.item
    }

    func store(_ item: HNItem) {
        entries[item.id] = (item, Date())
        if entries.count > Self.sweepThreshold {
            let now = Date()
            entries = entries.filter { now.timeIntervalSince($0.value.storedAt) < Self.ttl }
        }
    }

    func invalidate(_ ids: [Int]) {
        for id in ids { entries[id] = nil }
    }
}

struct HNClient {
    static let shared = HNClient()

    /// Upper bound on in-flight item requests. A busy thread is thousands of
    /// items, and firing them all at once buys nothing once the connection is
    /// saturated — it just stalls whatever else the app needs.
    private static let maxConcurrentFetches = 16

    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Ordered list of the current top-story IDs (up to ~500).
    func topStoryIDs() async throws -> [Int] {
        try await get([Int].self, path: "topstories.json")
    }

    /// Fetch a single item by ID, serving a fresh cached copy when available.
    func item(_ id: Int) async throws -> HNItem {
        if let cached = await ItemCache.shared.cached(id) {
            return cached
        }
        let item = try await get(HNItem.self, path: "item/\(id).json")
        await ItemCache.shared.store(item)
        return item
    }

    /// Fetch many items concurrently while preserving the input order, keeping
    /// at most `maxConcurrentFetches` requests in flight. Pass `refresh: true`
    /// to bypass the cache and fetch live copies.
    ///
    /// Individual fetches are allowed to fail without aborting the batch: a
    /// single transient network error or a deleted item (which the API returns
    /// as `null` and fails to decode) would otherwise take down the whole page.
    /// Failed items are simply dropped. If every fetch fails for a non-empty
    /// request, the error is rethrown so callers can show a retry prompt.
    func items(_ ids: [Int], refresh: Bool = false) async throws -> [HNItem] {
        if refresh {
            await ItemCache.shared.invalidate(ids)
        }
        return try await withThrowingTaskGroup(of: (Int, Result<HNItem, Error>).self) { group in
            func fetch(_ index: Int) {
                let id = ids[index]
                group.addTask {
                    do { return (index, .success(try await item(id))) }
                    catch { return (index, .failure(error)) }
                }
            }

            var queued = min(Self.maxConcurrentFetches, ids.count)
            for index in 0..<queued { fetch(index) }

            var results = [(Int, HNItem)]()
            var lastError: Error?
            for try await (index, result) in group {
                switch result {
                case .success(let item): results.append((index, item))
                case .failure(let error): lastError = error
                }
                // Top the group back up as each fetch lands.
                if queued < ids.count {
                    fetch(queued)
                    queued += 1
                }
            }
            if results.isEmpty, let lastError, !ids.isEmpty {
                throw lastError
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Fetch an entire comment thread, keyed by item ID.
    ///
    /// Walks the tree breadth-first, fetching each depth level as one batch, so
    /// the round trips scale with the thread's depth rather than its size.
    /// Callers that only want the cache warmed can discard the result.
    func thread(rootIDs: [Int], refresh: Bool = false) async throws -> [Int: HNItem] {
        var byID: [Int: HNItem] = [:]
        var level = rootIDs
        while !level.isEmpty {
            // A prefetch whose row scrolled away should stop between levels
            // rather than walk the rest of the thread.
            try Task.checkCancellation()
            let fetched = try await items(level, refresh: refresh)
            for item in fetched { byID[item.id] = item }
            // Skipping IDs already seen keeps a malformed reply cycle from
            // looping forever.
            level = fetched.flatMap { $0.kids ?? [] }.filter { byID[$0] == nil }
        }
        return byID
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let (data, response) = try await session.data(from: base.appending(path: path))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
