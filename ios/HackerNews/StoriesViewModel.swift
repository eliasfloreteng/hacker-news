//
//  StoriesViewModel.swift
//  HackerNews
//
//  Drives the paginated top-stories list (explicit pages, not infinite scroll).
//

import Foundation
import Observation

@MainActor
@Observable
final class StoriesViewModel {
    static let pageSize = 30

    private(set) var stories: [HNItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Zero-based index of the page currently shown.
    private(set) var page = 0
    private var allIDs: [Int] = []

    var pageCount: Int {
        max(1, Int(ceil(Double(allIDs.count) / Double(Self.pageSize))))
    }

    var humanPage: Int { page + 1 }
    var canGoNext: Bool { page + 1 < pageCount }
    var canGoPrevious: Bool { page > 0 }

    /// Fetch the list of IDs once, then load the first page.
    func loadInitial() async {
        guard allIDs.isEmpty else { return }
        await reload()
    }

    /// Re-fetch the ID list from scratch and reload the current page.
    func reload() async {
        do {
            allIDs = try await HNClient.shared.topStoryIDs()
            if page >= pageCount { page = 0 }
            await loadCurrentPage()
        } catch {
            errorMessage = "Couldn't load stories. Pull to retry."
        }
    }

    func goToNextPage() async {
        guard canGoNext else { return }
        page += 1
        await loadCurrentPage()
    }

    func goToPreviousPage() async {
        guard canGoPrevious else { return }
        page -= 1
        await loadCurrentPage()
    }

    private func loadCurrentPage() async {
        isLoading = true
        errorMessage = nil
        stories = []
        defer { isLoading = false }

        let start = page * Self.pageSize
        guard start < allIDs.count else { stories = []; return }
        let pageIDs = Array(allIDs[start..<min(start + Self.pageSize, allIDs.count)])

        do {
            stories = try await HNClient.shared.items(pageIDs)
        } catch {
            errorMessage = "Couldn't load this page. Pull to retry."
        }
    }
}
