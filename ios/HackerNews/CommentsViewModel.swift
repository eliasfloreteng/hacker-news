//
//  CommentsViewModel.swift
//  HackerNews
//
//  Builds the comment tree for a story. The whole thread is fetched before the
//  first render: rows never appear underneath the user mid-scroll, and a saved
//  scroll position or collapsed comment always has a row to attach to, however
//  deep in the thread it sits.
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
    /// Replaced on refresh, so the header's score and the thread's roots both
    /// come from the same up-to-date copy.
    private(set) var story: HNItem
    private(set) var roots: [CommentNode] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(story: HNItem) {
        self.story = story
    }

    /// Depth-first list of currently visible nodes. A node hidden by a collapsed
    /// ancestor is simply skipped.
    var visibleNodes: [CommentNode] {
        flatten(roots)
    }

    private func flatten(_ nodes: [CommentNode]) -> [CommentNode] {
        var out: [CommentNode] = []
        for node in nodes {
            out.append(node)
            if !node.collapsed {
                out.append(contentsOf: flatten(node.children))
            }
        }
        return out
    }

    func load() async {
        guard roots.isEmpty else { return }
        await fetchThread(refresh: false)
    }

    /// Pull-to-refresh: drop the existing tree and re-fetch from live data,
    /// bypassing the cache.
    func refresh() async {
        await fetchThread(refresh: true)
    }

    private func fetchThread(refresh: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // A pull re-fetches the story first. Its `kids` is what defines the
        // thread's roots, so refreshing only the comments we already know about
        // would never turn up a new top-level one.
        if refresh, let fresh = try? await HNClient.shared.item(story.id, refresh: true) {
            story = fresh
        }

        guard let kids = story.kids, !kids.isEmpty else {
            roots = []
            return
        }
        do {
            let items = try await HNClient.shared.thread(rootIDs: kids, refresh: refresh)
            roots = Self.nodes(for: kids, in: items, depth: 0)
        } catch {
            errorMessage = "Couldn't load comments."
        }
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
    private static func path(to id: Int, in nodes: [CommentNode]) -> [CommentNode]? {
        for node in nodes {
            if node.id == id { return [node] }
            if let rest = path(to: id, in: node.children) { return [node] + rest }
        }
        return nil
    }

    /// Assemble nodes for `ids` from an already-fetched thread, recursing into
    /// each comment's replies. Dead and deleted comments are dropped along with
    /// their subtrees, matching how HN hides them. An ID missing from `items`
    /// means its fetch failed, and is likewise skipped.
    private static func nodes(for ids: [Int], in items: [Int: HNItem], depth: Int) -> [CommentNode] {
        ids.compactMap { items[$0] }
            .filter { !$0.isDeadOrDeleted }
            .map { item in
                let node = CommentNode(item: item, depth: depth)
                node.children = nodes(for: item.kids ?? [], in: items, depth: depth + 1)
                return node
            }
    }
}
