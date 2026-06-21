//
//  CommentsView.swift
//  HackerNews
//
//  Threaded comments. Tapping a comment collapses it: its descendants are
//  hidden while the comment itself stays in place.
//

import SwiftUI

struct CommentsView: View {
    @State private var model: CommentsViewModel
    @Environment(\.openURL) private var openURL
    @Environment(VisitedStore.self) private var visited

    init(story: HNItem) {
        _model = State(initialValue: CommentsViewModel(story: story))
    }

    var body: some View {
        List {
            Section {
                storyHeader
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
                        .task { await node.loadChildrenIfNeeded() }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { visited.markVisited(model.story.id) }
        .task { await model.load() }
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
            withAnimation(.easeInOut(duration: 0.15)) {
                node.collapsed.toggle()
            }
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
