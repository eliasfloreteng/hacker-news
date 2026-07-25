//
//  ItemCacheTests.swift
//  HackerNewsTests
//
//  The cache swallows its own I/O errors by design — a cache that throws is
//  worse than one that misses — so a broken snapshot would otherwise show up
//  only as the app quietly never being fast. These tests exercise the real file.
//

import Foundation
import Testing
@testable import HackerNews

private func makeItem(id: Int, type: String, score: Int? = nil) -> HNItem {
    HNItem(
        id: id, type: type, by: "elias", time: 1_700_000_000, text: "hello",
        url: nil, title: "A story", score: score, descendants: nil,
        kids: [id + 1], deleted: nil, dead: nil
    )
}

private func temporaryCacheURL() -> URL {
    URL.temporaryDirectory.appending(path: "ItemCacheTests-\(UUID().uuidString).json")
}

struct ItemCacheTests {

    @Test func servesStoredItems() async {
        let cache = ItemCache(fileURL: temporaryCacheURL())
        await cache.store(makeItem(id: 1, type: "story", score: 42))

        let cached = await cache.cached(1)
        #expect(cached?.score == 42)
        #expect(await cache.cached(999) == nil)
    }

    /// The whole point of the disk layer: a fresh process starts warm.
    @Test func snapshotSurvivesANewInstance() async {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = ItemCache(fileURL: url)
        await writer.store(makeItem(id: 7, type: "comment"))
        await writer.storeTopStoryIDs([7, 8, 9])
        await writer.flush()

        let reader = ItemCache(fileURL: url)
        #expect(await reader.cached(7)?.kids == [8])
        #expect(await reader.cachedTopStoryIDs() == [7, 8, 9])
    }

    /// Freshness follows what the entry holds, so a day-old comment is still
    /// served while a day-old score is not.
    @Test func staleEntriesAreNotServed() async {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Write a snapshot dated well in the past, then read it back through a
        // new instance — the only way to age an entry without waiting.
        let aged = Date().addingTimeInterval(-(ItemCache.storyTTL + 60))
        try? encodedSnapshot(
            entries: [
                1: (makeItem(id: 1, type: "story", score: 42), aged),
                2: (makeItem(id: 2, type: "comment"), aged),
            ],
            topStories: ([1, 2], aged)
        ).write(to: url)

        let cache = ItemCache(fileURL: url)
        #expect(await cache.cached(1) == nil, "a story past its TTL is stale")
        #expect(await cache.cached(2) != nil, "a comment outlives a story")
        #expect(await cache.cachedTopStoryIDs() == nil, "the ordering is the first thing to go")
    }

    /// A flush from an instance that never read anything must not wipe the file.
    @Test func flushingBeforeAnyReadKeepsTheSnapshot() async {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = ItemCache(fileURL: url)
        await writer.store(makeItem(id: 3, type: "comment"))
        await writer.flush()

        await ItemCache(fileURL: url).flush()

        #expect(await ItemCache(fileURL: url).cached(3) != nil)
    }

    @Test func missingSnapshotIsNotAnError() async {
        let cache = ItemCache(fileURL: temporaryCacheURL())
        #expect(await cache.cached(1) == nil)
        #expect(await cache.cachedTopStoryIDs() == nil)
    }

    @Test func corruptSnapshotIsDiscarded() async {
        let url = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("not json".utf8).write(to: url)

        let cache = ItemCache(fileURL: url)
        #expect(await cache.cached(1) == nil)

        // And the cache is still usable afterwards.
        await cache.store(makeItem(id: 1, type: "story", score: 5))
        #expect(await cache.cached(1)?.score == 5)
    }

    /// Mirrors the private `Snapshot` shape so tests can plant entries with a
    /// chosen age. If the stored format changes, this fails loudly.
    private func encodedSnapshot(
        entries: [Int: (item: HNItem, storedAt: Date)],
        topStories: (ids: [Int], storedAt: Date)?
    ) -> Data {
        struct Entry: Encodable {
            let item: HNItem
            let storedAt: Date
        }
        struct TopStories: Encodable {
            let ids: [Int]
            let storedAt: Date
        }
        struct Snapshot: Encodable {
            let entries: [Int: Entry]
            let topStories: TopStories?
        }
        let snapshot = Snapshot(
            entries: entries.mapValues { Entry(item: $0.item, storedAt: $0.storedAt) },
            topStories: topStories.map { TopStories(ids: $0.ids, storedAt: $0.storedAt) }
        )
        return try! JSONEncoder().encode(snapshot)
    }
}
