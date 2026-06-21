//
//  CommentPrefetcher.swift
//  HackerNews
//
//  Warms the item cache with a story's top-level comments while its row is on
//  screen, so opening the discussion feels instant. Prefetches are debounced so
//  rows the user flicks past don't fire, capped to roughly the first screenful
//  of comments to stay light on the network, and deduped against the cache TTL.
//

import Foundation

@MainActor
final class CommentPrefetcher {
    static let shared = CommentPrefetcher()

    /// Only the first comments are worth warming — they're what the reader sees
    /// before scrolling. The rest fill in on demand when the thread opens.
    private static let prefetchLimit = 10

    /// Wait out quick scrolling before spending a request on a row.
    private static let debounce: Duration = .milliseconds(300)

    /// Skip re-prefetching a story whose comments are still cache-fresh. Kept a
    /// touch under `ItemCache.ttl` so an entry doesn't expire moments after.
    private static let revisitInterval: TimeInterval = ItemCache.ttl - 10

    private var tasks: [Int: Task<Void, Never>] = [:]
    private var lastPrefetched: [Int: Date] = [:]

    private init() {}

    /// Begin warming a story's top-level comments. No-op for stories without
    /// comments, ones already in flight, or ones prefetched recently.
    func prefetch(_ story: HNItem) {
        let id = story.id
        guard let kids = story.kids, !kids.isEmpty, tasks[id] == nil else { return }
        if let last = lastPrefetched[id], Date().timeIntervalSince(last) < Self.revisitInterval {
            return
        }

        let ids = Array(kids.prefix(Self.prefetchLimit))
        tasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            _ = try? await HNClient.shared.items(ids)
            guard let self, !Task.isCancelled else { return }
            self.lastPrefetched[id] = Date()
            self.tasks[id] = nil
        }
    }

    /// Stop warming a story whose row scrolled off before the debounce elapsed.
    func cancel(_ story: HNItem) {
        tasks[story.id]?.cancel()
        tasks[story.id] = nil
    }
}
