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

    var body: some View {
        NavigationStack {
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
        .task { await model.loadInitial() }
    }

    private var storyList: some View {
        List {
            ForEach(Array(model.stories.enumerated()), id: \.element.id) { index, story in
                StoryRow(story: story, rank: model.page * StoriesViewModel.pageSize + index + 1)
                    .listRowSeparator(.visible)
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
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                // Title — opens the link in the default browser.
                Button {
                    visited.markVisited(story.id)
                    openURL(story.destinationURL)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(story.title ?? "(untitled)")
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(isVisited ? .secondary : .primary)
                        if let host = story.displayHost {
                            Text(host)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)

                metadata
            }
        }
        .padding(.vertical, 4)
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            Label("\(story.score ?? 0)", systemImage: "arrow.up")
                .foregroundStyle(isVisited ? .tertiary : .secondary)

            if let by = story.by {
                Text(by)
            }
            Text(RelativeTime.string(from: story.date))

            Spacer()

            // Comments — opens the in-app discussion view.
            NavigationLink(value: story) {
                Label("\(story.descendants ?? 0)", systemImage: "bubble.left")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("commentsLink")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
