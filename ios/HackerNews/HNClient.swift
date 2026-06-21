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
    func items(_ ids: [Int], refresh: Bool = false) async throws -> [HNItem] {
        if refresh {
            await ItemCache.shared.invalidate(ids)
        }
        return try await withThrowingTaskGroup(of: (Int, HNItem).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await item(id)) }
            }
            var results = [(Int, HNItem)]()
            for try await pair in group {
                results.append(pair)
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
