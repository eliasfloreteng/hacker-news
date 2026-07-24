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
    ///
    /// Pull-to-refresh passes `refresh: true`: it bypasses the item cache (a
    /// pull within the TTL would otherwise return the very scores already on
    /// screen) and keeps the existing rows in place while loading, so the list
    /// — and with it the refresh control driving the gesture — isn't torn down.
    func reload(refresh: Bool = false) async {
        do {
            allIDs = try await HNClient.shared.topStoryIDs()
            if page >= pageCount { page = 0 }
            await loadCurrentPage(refresh: refresh)
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

    private func loadCurrentPage(refresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        // Page navigation blanks the list so the old page doesn't linger under
        // a spinner; a refresh replaces the rows in place instead.
        if !refresh { stories = [] }
        defer { isLoading = false }

        let start = page * Self.pageSize
        guard start < allIDs.count else { stories = []; return }
        let pageIDs = Array(allIDs[start..<min(start + Self.pageSize, allIDs.count)])

        do {
            stories = try await HNClient.shared.items(pageIDs, refresh: refresh)
        } catch {
            errorMessage = "Couldn't load this page. Pull to retry."
        }
    }
}
