//
//  CommentPrefetcher.swift
//  HackerNews
//
//  Warms the item cache with a story's comments while its row is on screen, so
//  opening the discussion feels instant. We fetch the entire thread because the
//  thread view builds the whole tree before it renders — warming only part of it
//  would still leave the spinner up. Prefetches are debounced so rows the user
//  flicks past don't fire, and deduped against the cache TTL.
//

import Foundation

@MainActor
final class CommentPrefetcher {
    static let shared = CommentPrefetcher()

    /// Wait out quick scrolling before spending a request on a row.
    private static let debounce: Duration = .milliseconds(300)

    /// Skip re-prefetching a story whose comments are still cache-fresh — the
    /// walk would find everything already cached and spend a slot doing nothing.
    private static let revisitInterval: TimeInterval = ItemCache.commentTTL

    /// How many threads to warm at once. A screenful of rows would otherwise
    /// each start a walk of a whole thread and crowd out the story the user
    /// actually taps. Speculative work should never outbid the real request.
    private static let maxConcurrentWalks = 2

    private var tasks: [Int: Task<Void, Never>] = [:]
    private var lastPrefetched: [Int: Date] = [:]

    private init() {}

    /// Begin warming a story's comment thread. No-op for stories without
    /// comments, ones already in flight, or ones prefetched recently. Also a
    /// no-op while the walk budget is spent — prefetching is best-effort, and a
    /// story that misses out simply loads on demand when opened.
    func prefetch(_ story: HNItem) {
        let id = story.id
        guard let kids = story.kids, !kids.isEmpty, tasks[id] == nil,
              tasks.count < Self.maxConcurrentWalks else { return }
        if let last = lastPrefetched[id], Date().timeIntervalSince(last) < Self.revisitInterval {
            return
        }

        tasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            _ = try? await HNClient.shared.thread(rootIDs: kids)
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
