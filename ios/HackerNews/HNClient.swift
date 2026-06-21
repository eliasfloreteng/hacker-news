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
    }

    func invalidate(_ ids: [Int]) {
        for id in ids { entries[id] = nil }
    }
}

struct HNClient {
    static let shared = HNClient()

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

    /// Fetch many items concurrently while preserving the input order. Pass
    /// `refresh: true` to bypass the cache and fetch live copies.
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
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do { return (index, .success(try await item(id))) }
                    catch { return (index, .failure(error)) }
                }
            }
            var results = [(Int, HNItem)]()
            var lastError: Error?
            for try await (index, result) in group {
                switch result {
                case .success(let item): results.append((index, item))
                case .failure(let error): lastError = error
                }
            }
            if results.isEmpty, let lastError, !ids.isEmpty {
                throw lastError
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let (data, response) = try await session.data(from: base.appending(path: path))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
