//
//  CommentsView.swift
//  HackerNews
//
//  Threaded comments. Tapping a comment collapses it: its descendants are
//  hidden while the comment itself stays in place.
//

import SwiftUI

private let commentsCoordinateSpace = "commentsList"

struct CommentsView: View {
    @State private var model: CommentsViewModel
    /// ID of the row currently pinned to the top of the viewport (a comment ID,
    /// or the story ID when the header is showing). Driven by row geometry.
    @State private var topVisibleID: Int?
    @Environment(\.openURL) private var openURL
    @Environment(VisitedStore.self) private var visited

    init(story: HNItem) {
        _model = State(initialValue: CommentsViewModel(story: story))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    storyHeader
                        .trackTopOffset(id: model.story.id)
                }

                if model.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowSeparator(.hidden)
                } else if let error = model.errorMessage {
                    Text(error).foregroundStyle(.secondary)
                } else if model.roots.isEmpty {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(model.visibleNodes) { node in
                        CommentRow(node: node)
                            .trackTopOffset(id: node.id)
                            .task { await node.loadChildrenIfNeeded() }
                    }
                }
            }
            .listStyle(.plain)
            .coordinateSpace(.named(commentsCoordinateSpace))
            .onPreferenceChange(RowTopOffsetKey.self) { offsets in
                topVisibleID = Self.topmost(of: offsets)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .onAppear { visited.markVisited(model.story.id) }
            .onDisappear {
                if let topVisibleID {
                    CommentScrollStore.shared.setTop(topVisibleID, for: model.story.id)
                }
            }
            .task {
                await model.load()
                // Restore the previous reading position once the rows are laid out.
                guard let saved = CommentScrollStore.shared.top(for: model.story.id),
                      saved != model.story.id else { return }
                try? await Task.sleep(for: .milliseconds(50))
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) { proxy.scrollTo(saved, anchor: .top) }
            }
        }
    }

    /// The row pinned to the top edge: the one whose top is closest to (but not
    /// below) the viewport's top. Falls back to the first row below the edge.
    private static func topmost(of offsets: [Int: CGFloat]) -> Int? {
        let aboveEdge = offsets.filter { $0.value <= 1 }
        if let pinned = aboveEdge.max(by: { $0.value < $1.value }) {
            return pinned.key
        }
        return offsets.min(by: { $0.value < $1.value })?.key
    }

    private var storyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                visited.markVisited(model.story.id)
                openURL(model.story.destinationURL)
            } label: {
                Text(model.story.title ?? "(untitled)")
                    .font(.headline)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)

            if let text = model.story.text, !text.isEmpty {
                Text(HTMLText.plain(from: text))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(model.story.score ?? 0)", systemImage: "arrow.up")
                if let by = model.story.by { Text(by) }
                Text(RelativeTime.string(from: model.story.date))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CommentRow: View {
    let node: CommentNode

    private let indentPerLevel: CGFloat = 12
    private let maxIndentLevel = 8

    var body: some View {
        Button {
            // Collapsing only makes sense when there are children to hide.
            guard node.hasChildren else { return }
            node.collapsed.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                indentBar
                VStack(alignment: .leading, spacing: 4) {
                    header
                    if let text = node.item.text {
                        Text(HTMLText.plain(from: text))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            // Make the entire row rect tappable, including the trailing spacer.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("comment")
        .padding(.leading, CGFloat(min(node.depth, maxIndentLevel)) * indentPerLevel)
    }

    @ViewBuilder private var indentBar: some View {
        if node.depth > 0 {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 2)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(node.item.by ?? "anonymous")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(RelativeTime.string(from: node.item.date))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            if node.hasChildren {
                Label(
                    node.collapsed ? "\(node.childCount)" : "",
                    systemImage: node.collapsed ? "chevron.right" : "chevron.down"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

// MARK: - Scroll position tracking

/// Collects each visible row's top offset (in the list's coordinate space)
/// keyed by row ID, so the view can figure out which row sits at the top.
private struct RowTopOffsetKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    func trackTopOffset(id: Int) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowTopOffsetKey.self,
                    value: [id: geo.frame(in: .named(commentsCoordinateSpace)).minY]
                )
            }
        )
    }
}
