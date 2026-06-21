//
//  CommentsViewModel.swift
//  HackerNews
//
//  Lazily builds the comment tree for a story. Children load when their parent
//  first appears, so we never fetch a whole thread up front.
//

import Foundation
import Observation

@MainActor
@Observable
final class CommentNode: Identifiable {
    let item: HNItem
    let depth: Int

    /// When true the node's descendants are hidden — but the node itself stays
    /// visible (per the app's collapse behaviour).
    var collapsed = false
    var children: [CommentNode] = []
    var hasLoadedChildren = false
    private var isLoading = false

    nonisolated var id: Int { item.id }
    var childCount: Int { item.kids?.count ?? 0 }
    var hasChildren: Bool { childCount > 0 }

    init(item: HNItem, depth: Int) {
        self.item = item
        self.depth = depth
    }

    func loadChildrenIfNeeded() async {
        guard !hasLoadedChildren, !isLoading, let kids = item.kids, !kids.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let items = try? await HNClient.shared.items(kids) {
            children = items
                .filter { !$0.isDeadOrDeleted }
                .map { CommentNode(item: $0, depth: depth + 1) }
        }
        hasLoadedChildren = true
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let kids = story.kids, !kids.isEmpty else { return }
        do {
            let items = try await HNClient.shared.items(kids)
            roots = items
                .filter { !$0.isDeadOrDeleted }
                .map { CommentNode(item: $0, depth: 0) }
        } catch {
            errorMessage = "Couldn't load comments."
        }
    }
}
