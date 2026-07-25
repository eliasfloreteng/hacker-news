//
//  CommentsViewModelStoreTests.swift
//  HackerNewsTests
//
//  Reuse is the whole point of the store — a regression here doesn't break
//  anything visible, it just quietly makes every visit rebuild the thread again.
//

import Foundation
import Testing
@testable import HackerNews

private func makeStory(id: Int) -> HNItem {
    HNItem(
        id: id, type: "story", by: "elias", time: 1_700_000_000, text: nil,
        url: nil, title: "Story \(id)", score: 10, descendants: 2,
        kids: [id * 10], deleted: nil, dead: nil
    )
}

@MainActor
struct CommentsViewModelStoreTests {

    @Test func returnsTheSameModelForAStoryItAlreadyHolds() {
        let store = CommentsViewModelStore()
        let first = store.model(for: makeStory(id: 1))
        let second = store.model(for: makeStory(id: 1))
        #expect(first === second)
    }

    @Test func distinctStoriesGetDistinctModels() {
        let store = CommentsViewModelStore()
        #expect(store.model(for: makeStory(id: 1)) !== store.model(for: makeStory(id: 2)))
    }

    /// The case that prompted the store: open a thread, visit another, come back.
    @Test func aThreadSurvivesVisitingAnother() {
        let store = CommentsViewModelStore(limit: 2)
        let original = store.model(for: makeStory(id: 1))
        _ = store.model(for: makeStory(id: 2))
        #expect(store.model(for: makeStory(id: 1)) === original)
    }

    @Test func theLeastRecentlyUsedThreadIsEvictedFirst() {
        let store = CommentsViewModelStore(limit: 2)
        let first = store.model(for: makeStory(id: 1))
        _ = store.model(for: makeStory(id: 2))
        // Touch 1 so 2 becomes the least recent, then push past the limit.
        _ = store.model(for: makeStory(id: 1))
        _ = store.model(for: makeStory(id: 3))

        #expect(store.model(for: makeStory(id: 1)) === first, "recently used, still held")
        #expect(store.model(for: makeStory(id: 2)) !== first)
    }

    @Test func doesNotGrowPastItsLimit() {
        let store = CommentsViewModelStore(limit: 2)
        let first = store.model(for: makeStory(id: 1))
        for id in 2...5 { _ = store.model(for: makeStory(id: id)) }
        #expect(store.model(for: makeStory(id: 1)) !== first, "evicted long ago")
    }
}
