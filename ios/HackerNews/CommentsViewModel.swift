//
//  CommentsViewModel.swift
//  HackerNews
//
//  Builds the comment tree for a story. The whole thread arrives in one request
//  (see `HNClient.commentThread`) and is built before anything renders, so rows
//  never appear underneath the user mid-scroll. It's shown a page of top-level
//  comments at a time, with "Load more" revealing the next.
//

import Foundation
import Observation

@MainActor
@Observable
final class CommentNode: Identifiable {
    let item: HNItem
    let depth: Int

    /// When true the node's descendants are hidden — but the node itself stays
    /// visible (per the app's collapse behaviour). Persisted so the thread keeps
    /// its collapsed shape across visits.
    var collapsed: Bool {
        didSet {
            guard collapsed != oldValue else { return }
            CollapsedStore.shared.setCollapsed(collapsed, for: item.id)
        }
    }
    var children: [CommentNode] = []

    nonisolated var id: Int { item.id }
    /// Replies actually shown under this comment. Counted from the built tree
    /// rather than `item.kids`, so dead and deleted replies aren't promised in
    /// the collapsed badge.
    var childCount: Int { children.count }
    var hasChildren: Bool { !children.isEmpty }

    init(item: HNItem, depth: Int) {
        self.item = item
        self.depth = depth
        self.collapsed = CollapsedStore.shared.isCollapsed(item.id)
    }
}

/// Keeps recently opened threads alive across navigation.
///
/// A pushed `CommentsView` is a fresh view every time, so without this each
/// visit rebuilds its view model from nothing: a cache lookup per comment and a
/// whole new node tree, with the spinner up throughout. The items are cached, so
/// none of it hits the network — it still reads as a load on a big thread, and
/// it discards the tree the user was looking at moments ago.
@MainActor
final class CommentsViewModelStore {
    static let shared = CommentsViewModelStore()

    /// How many threads to hold. Each keeps its entire node tree alive, so this
    /// trades memory for the stepping-between-discussions case it exists to
    /// serve; beyond a handful the memory stops being worth it.
    private let limit: Int

    private var models: [Int: CommentsViewModel] = [:]
    /// Story IDs, least recently used first.
    private var usage: [Int] = []

    init(limit: Int = 5) {
        self.limit = limit
    }

    /// The view model for a story, reusing the one from a previous visit when
    /// it's still held. The retained model keeps its own copy of the story, so
    /// the header shows what it showed last time until a pull refreshes it.
    func model(for story: HNItem) -> CommentsViewModel {
        usage.removeAll { $0 == story.id }
        usage.append(story.id)

        if let existing = models[story.id] { return existing }

        let model = CommentsViewModel(story: story)
        models[story.id] = model
        while usage.count > limit {
            models.removeValue(forKey: usage.removeFirst())
        }
        return model
    }
}

@MainActor
@Observable
final class CommentsViewModel {
    /// Top-level comments shown per page. Each comes with its whole reply tree,
    /// as on the HN site, so this is a few screens of reading.
    static let pageSize = 10

    /// Replaced on refresh, so the header's score and the thread's roots both
    /// come from the same up-to-date copy.
    private(set) var story: HNItem
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Every top-level comment in the thread, built up front. The thread
    /// arrives in a single request, so paging is only about how much is shown.
    private var allRoots: [CommentNode] = []
    private var shownRootCount = 0

    init(story: HNItem) {
        self.story = story
    }

    /// The top-level comments showing so far.
    var roots: ArraySlice<CommentNode> {
        allRoots.prefix(shownRootCount)
    }

    /// Whether there are top-level comments past the ones showing.
    var hasMore: Bool {
        shownRootCount < allRoots.count
    }

    /// Depth-first list of currently visible nodes. A node hidden by a collapsed
    /// ancestor is simply skipped.
    var visibleNodes: [CommentNode] {
        flatten(roots)
    }

    private func flatten(_ nodes: some Sequence<CommentNode>) -> [CommentNode] {
        var out: [CommentNode] = []
        for node in nodes {
            out.append(node)
            if !node.collapsed {
                out.append(contentsOf: flatten(node.children))
            }
        }
        return out
    }

    /// Fetch the thread and show its first page. When `rootID` names a
    /// top-level comment further down, every page through the one holding it
    /// shows too — that's where the user left off, and restoring the scroll
    /// position needs its row.
    func load(through rootID: Int? = nil) async {
        guard allRoots.isEmpty, !isLoading else { return }
        await fetchThread(refresh: false)
        shownRootCount = rootCount(through: rootID)
    }

    /// Pull-to-refresh: drop the existing tree and re-fetch from live data,
    /// bypassing the cache. As many pages as were showing stay showing, so a
    /// pull doesn't throw away what the user had opened up.
    func refresh() async {
        let shown = shownRootCount
        await fetchThread(refresh: true)
        shownRootCount = min(max(shown, Self.pageSize), allRoots.count)
    }

    /// Show the next page of top-level comments.
    func loadMore() {
        shownRootCount = min(shownRootCount + Self.pageSize, allRoots.count)
    }

    private func fetchThread(refresh: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // A pull re-fetches the story too, so the header's score and comment
        // count move along with the thread.
        if refresh, let fresh = try? await HNClient.shared.item(story.id, refresh: true) {
            story = fresh
        }

        guard story.kids?.isEmpty == false else {
            allRoots = []
            return
        }
        do {
            let thread = try await HNClient.shared.commentThread(for: story, refresh: refresh)
            allRoots = Self.nodes(for: thread.rootIDs, in: thread.items, depth: 0)
        } catch {
            errorMessage = "Couldn't load comments."
        }
    }

    /// The number of top-level comments to show so `rootID` is among them,
    /// rounded up to whole pages. Just the first page when it's absent or no
    /// longer in the thread.
    private func rootCount(through rootID: Int?) -> Int {
        let pages = rootID
            .flatMap { id in allRoots.firstIndex { $0.id == id } }
            .map { $0 / Self.pageSize + 1 } ?? 1
        return min(pages * Self.pageSize, allRoots.count)
    }

    /// The top-level comment whose subtree holds `id`, or nil if it isn't
    /// showing. A top-level comment is its own root.
    func rootID(containing id: Int) -> Int? {
        Self.path(to: id, in: roots)?.first?.id
    }

    /// Resolves a saved scroll position to a row that actually exists on screen.
    /// The saved comment is used as-is when it's visible; when a collapsed
    /// ancestor hides it, the outermost such ancestor stands in for it. Returns
    /// nil if the comment is no longer in the thread at all.
    func restorationTarget(for id: Int) -> Int? {
        guard let path = Self.path(to: id, in: roots) else { return nil }
        // Everything below the first collapsed node on the path is hidden.
        return path.dropLast().first(where: \.collapsed)?.id ?? id
    }

    /// The chain of nodes from a root down to `id`, inclusive.
    private static func path(to id: Int, in nodes: some Sequence<CommentNode>) -> [CommentNode]? {
        for node in nodes {
            if node.id == id { return [node] }
            if let rest = path(to: id, in: node.children) { return [node] + rest }
        }
        return nil
    }

    /// Assemble nodes for `ids` from an already-fetched thread, recursing into
    /// each comment's replies. Dead and deleted comments are dropped, as HN
    /// drops them — unless replies survive underneath, which HN keeps in place
    /// under a "[deleted]" stand-in. An ID missing from `items` means its fetch
    /// failed, and is likewise skipped.
    private static func nodes(for ids: [Int], in items: [Int: HNItem], depth: Int) -> [CommentNode] {
        ids.compactMap { items[$0] }.compactMap { item in
            let node = CommentNode(item: item, depth: depth)
            node.children = nodes(for: item.kids ?? [], in: items, depth: depth + 1)
            return item.isDeadOrDeleted && node.children.isEmpty ? nil : node
        }
    }
}
