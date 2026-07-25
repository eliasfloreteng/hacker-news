//
//  ItemCache.swift
//  HackerNews
//
//  Two-tier cache for everything fetched from the API: an in-memory map for the
//  session, backed by a JSON snapshot on disk so a cold launch starts from the
//  last session's data instead of an empty screen.
//
//  Freshness is deliberately generous. Pull-to-refresh is the app's "give me
//  live data" gesture and bypasses every layer here, so the cache can favour
//  showing something instantly over showing the very latest.
//

import Foundation

actor ItemCache {
    static let shared = ItemCache()

    /// A comment is all but immutable once posted — what changes is its reply
    /// list, and a thread that has moved on can wait for a pull-to-refresh.
    static let commentTTL: TimeInterval = 60 * 60 * 2

    /// A story's score and comment count move constantly, so its copy is
    /// trusted for far less time than the comments hanging off it.
    static let storyTTL: TimeInterval = 60 * 10

    /// The top-story ordering churns faster than anything else; caching it is
    /// about making a relaunch instant, not about avoiding the network for long.
    static let topStoriesTTL: TimeInterval = 60 * 5

    /// Entries expire lazily on lookup, which never happens for a comment the
    /// user doesn't come back to. Past this many we sweep the stale ones so an
    /// afternoon of browsing big threads doesn't retain every comment seen.
    private static let sweepThreshold = 5_000

    /// Cap on the snapshot so it stays quick to write and read back. Entries
    /// are dropped oldest-first, which is also least-likely-to-be-wanted-first.
    private static let maxPersistedEntries = 3_000

    /// How long writes are coalesced. Warming a thread stores hundreds of items
    /// in a burst; there is no point writing the file for each one.
    private static let saveDebounce: Duration = .seconds(5)

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var didLoad = false
    private var saveTask: Task<Void, Never>?

    /// The file location is injectable so tests can exercise a real round trip
    /// without trampling the running app's cache.
    init(fileURL: URL = ItemCache.defaultFileURL) {
        self.fileURL = fileURL
    }

    // MARK: - Items

    func cached(_ id: Int) -> HNItem? {
        loadIfNeeded()
        guard let entry = snapshot.entries[id] else { return nil }
        guard entry.isFresh else {
            snapshot.entries[id] = nil
            return nil
        }
        return entry.item
    }

    func store(_ item: HNItem) {
        loadIfNeeded()
        snapshot.entries[item.id] = Entry(item: item, storedAt: Date())
        if snapshot.entries.count > Self.sweepThreshold {
            snapshot.entries = snapshot.entries.filter(\.value.isFresh)
        }
        scheduleSave()
    }

    // MARK: - Top stories

    func cachedTopStoryIDs() -> [Int]? {
        loadIfNeeded()
        guard let stored = snapshot.topStories,
              Date().timeIntervalSince(stored.storedAt) < Self.topStoriesTTL else { return nil }
        return stored.ids
    }

    func storeTopStoryIDs(_ ids: [Int]) {
        loadIfNeeded()
        snapshot.topStories = TopStories(ids: ids, storedAt: Date())
        scheduleSave()
    }

    // MARK: - Persistence

    /// Write the snapshot now rather than waiting out the debounce. Called when
    /// the app backgrounds, where "later" may never come — iOS can suspend the
    /// process before a pending save fires.
    func flush() {
        // Load first: backgrounding before anything was read would otherwise
        // write this instance's empty snapshot over a perfectly good file.
        loadIfNeeded()
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    /// Where the snapshot lives. The caches directory is the honest home for it:
    /// every byte is re-fetchable, so the OS is welcome to reclaim it.
    static let defaultFileURL: URL = {
        let directory = URL.cachesDirectory.appending(path: "HackerNews", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "items.json")
    }()

    /// Read the snapshot back on first use. A snapshot that fails to decode —
    /// an interrupted write, or a build that changed `HNItem` — is simply
    /// discarded; it all re-fetches.
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = decoded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() {
        var toPersist = snapshot
        toPersist.entries = toPersist.entries.filter(\.value.isFresh)
        if toPersist.entries.count > Self.maxPersistedEntries {
            let newest = toPersist.entries
                .sorted { $0.value.storedAt > $1.value.storedAt }
                .prefix(Self.maxPersistedEntries)
            toPersist.entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(toPersist) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Stored shapes

    private struct Snapshot: Codable {
        var entries: [Int: Entry] = [:]
        var topStories: TopStories?
    }

    private struct TopStories: Codable {
        let ids: [Int]
        let storedAt: Date
    }

    private struct Entry: Codable {
        let item: HNItem
        let storedAt: Date

        /// Comments and stories age at very different rates, so an entry's
        /// lifetime follows what it holds.
        var isFresh: Bool {
            let ttl = item.type == "comment" ? ItemCache.commentTTL : ItemCache.storyTTL
            return Date().timeIntervalSince(storedAt) < ttl
        }
    }
}
