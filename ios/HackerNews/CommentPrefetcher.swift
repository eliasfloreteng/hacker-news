//
//  CommentPrefetcher.swift
//  HackerNews
//
//  Warms the item cache with a story's comments while its row is on screen, so
//  opening the discussion feels instant. A thread is one request for the HN
//  page, so the whole of it is warmed. Prefetches are debounced so rows the
//  user flicks past don't fire, and deduped against the cache TTL.
//

import Foundation

@MainActor
final class CommentPrefetcher {
    static let shared = CommentPrefetcher()

    /// Wait out quick scrolling before spending a request on a row.
    private static let debounce: Duration = .milliseconds(300)

    /// Skip re-prefetching a story whose comments are still cache-fresh — the
    /// fetch would be served from the cache and spend a slot doing nothing.
    private static let revisitInterval: TimeInterval = ItemCache.threadTTL

    /// How many threads to warm at once. A screenful of rows would otherwise
    /// each start a page download and crowd out the story the user actually
    /// taps. Speculative work should never outbid the real request.
    private static let maxConcurrentFetches = 2

    private var tasks: [Int: Task<Void, Never>] = [:]
    private var lastPrefetched: [Int: Date] = [:]

    private init() {}

    /// Begin warming a story's comment thread. No-op for stories without
    /// comments, ones already in flight, or ones prefetched recently. Also a
    /// no-op while the fetch budget is spent — prefetching is best-effort, and a
    /// story that misses out simply loads on demand when opened.
    func prefetch(_ story: HNItem) {
        let id = story.id
        guard story.kids?.isEmpty == false, tasks[id] == nil,
              tasks.count < Self.maxConcurrentFetches else { return }
        if let last = lastPrefetched[id], Date().timeIntervalSince(last) < Self.revisitInterval {
            return
        }

        tasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            _ = try? await HNClient.shared.commentThread(for: story)
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
