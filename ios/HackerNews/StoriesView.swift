//
//  StoriesView.swift
//  HackerNews
//
//  Paginated top-stories list.
//

import SwiftUI

struct StoriesView: View {
    @State private var model = StoriesViewModel()
    @State private var showingSettings = false
    @State private var path: [HNItem] = []
    @State private var router = NotificationRouter.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.isLoading && model.stories.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.errorMessage, model.stories.isEmpty {
                    ContentUnavailableView {
                        Label("No stories", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await model.reload() } }
                    }
                } else {
                    storyList
                }
            }
            .navigationTitle("Top Stories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: HNItem.self) { story in
                CommentsView(story: story)
            }
        }
        .task {
            await model.loadInitial()
            // Handle a notification that launched the app cold.
            await openPendingStory()
        }
        .onChange(of: router.pendingStoryID) { _, id in
            guard id != nil else { return }
            Task { await openPendingStory() }
        }
    }

    /// Pushes the comments for a story tapped in a notification, fetching the
    /// item if it isn't already on the current page.
    private func openPendingStory() async {
        guard let id = router.pendingStoryID else { return }
        router.pendingStoryID = nil

        if let story = model.stories.first(where: { $0.id == id }) {
            path = [story]
        } else if let story = try? await HNClient.shared.item(id) {
            path = [story]
        }
    }

    private var storyList: some View {
        List {
            ForEach(Array(model.stories.enumerated()), id: \.element.id) { index, story in
                StoryRow(story: story, rank: model.page * StoriesViewModel.pageSize + index + 1)
                    .listRowSeparator(.visible)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .onAppear { CommentPrefetcher.shared.prefetch(story) }
                    .onDisappear { CommentPrefetcher.shared.cancel(story) }
            }

            PaginationControls(model: model)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .refreshable { await model.reload() }
    }
}

private struct PaginationControls: View {
    let model: StoriesViewModel

    var body: some View {
        HStack {
            Button {
                Task { await model.goToPreviousPage() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!model.canGoPrevious)

            Spacer()
            Text("Page \(model.humanPage) of \(model.pageCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()

            Button {
                Task { await model.goToNextPage() }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .disabled(!model.canGoNext)
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 8)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

struct StoryRow: View {
    let story: HNItem
    let rank: Int

    @Environment(\.openURL) private var openURL
    @Environment(VisitedStore.self) private var visited

    private var isVisited: Bool { visited.isVisited(story.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(rank)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                // Title — opens the link in the default browser. Takes the
                // full row width so it wraps cleanly across lines.
                Button {
                    visited.markVisited(story.id)
                    openURL(story.destinationURL)
                } label: {
                    Text(story.title ?? "(untitled)")
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(isVisited ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // Source host on its own line so it never crowds the title.
                if let host = story.displayHost {
                    HStack(spacing: 4) {
                        Favicon(host: host)
                        Text(host)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                metadata
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if isVisited {
                Button {
                    visited.unmarkVisited(story.id)
                } label: {
                    Label("Mark as Not Read", systemImage: "circle")
                }
            } else {
                Button {
                    visited.markVisited(story.id)
                } label: {
                    Label("Mark as Read", systemImage: "checkmark.circle")
                }
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 14) {
            Label("\(story.score ?? 0)", systemImage: "arrow.up")
                .foregroundStyle(isVisited ? .tertiary : .secondary)

            if let by = story.by {
                Label(by, systemImage: "person")
                    .lineLimit(1)
            }

            Text(RelativeTime.string(from: story.date))

            Spacer(minLength: 8)

            // Comments — opens the in-app discussion view.
            NavigationLink(value: story) {
                Label("\(story.descendants ?? 0)", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("commentsLink")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.compactMetadata)
    }
}

/// Loads a site's favicon for the source-host line, falling back to a globe
/// glyph while loading or when no icon is available.
private struct Favicon: View {
    let host: String

    private var url: URL? {
        URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "globe")
            }
        }
        .frame(width: 13, height: 13)
    }
}

/// Tightens icon-and-text labels in the metadata row: small gap, baseline-ish
/// alignment, so score / author / comments read as compact units.
private struct CompactMetadataLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

private extension LabelStyle where Self == CompactMetadataLabelStyle {
    static var compactMetadata: CompactMetadataLabelStyle { .init() }
}
