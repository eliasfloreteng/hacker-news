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

@MainActor
@Observable
final class CommentsViewModel {
    let story: HNItem
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
