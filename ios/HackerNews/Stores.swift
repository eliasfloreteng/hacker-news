//
//  Stores.swift
//  HackerNews
//
//  Lightweight UserDefaults-backed persistence. Kept free of SwiftUI so the
//  same logic is usable from the background refresh task.
//

import Foundation
import Observation

enum DefaultsKey {
    static let visited = "visitedStoryIDs"
    static let notified = "notifiedStoryIDs"
    static let notificationsEnabled = "notificationsEnabled"
    static let pointsThreshold = "pointsThreshold"
    static let collapsed = "collapsedCommentIDs"
    static let scrollPosition = "commentScrollPositionByStory"
    static let legacyScrollTop = "commentScrollTopByStory"
}

/// Tracks which stories the user has opened in the browser.
@Observable
final class VisitedStore {
    static let shared = VisitedStore()

    private(set) var visited: Set<Int>

    private init() {
        let raw = UserDefaults.standard.array(forKey: DefaultsKey.visited) as? [Int] ?? []
        visited = Set(raw)
    }

    func isVisited(_ id: Int) -> Bool { visited.contains(id) }

    func markVisited(_ id: Int) {
        guard !visited.contains(id) else { return }
        visited.insert(id)
        persist()
    }

    func unmarkVisited(_ id: Int) {
        guard visited.contains(id) else { return }
        visited.remove(id)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(visited), forKey: DefaultsKey.visited)
    }

    /// Read the visited set directly from defaults (for use off the main actor).
    static func visitedIDs() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: DefaultsKey.visited) as? [Int] ?? [])
    }
}

/// Remembers which comments the user has collapsed so the thread looks the same
/// when they leave and come back. HN comment IDs are globally unique, so a flat
/// set keyed by comment ID is enough — no need to scope by story.
@Observable
final class CollapsedStore {
    static let shared = CollapsedStore()

    private var collapsed: Set<Int>

    private init() {
        let raw = UserDefaults.standard.array(forKey: DefaultsKey.collapsed) as? [Int] ?? []
        collapsed = Set(raw)
    }

    func isCollapsed(_ id: Int) -> Bool { collapsed.contains(id) }

    func setCollapsed(_ isCollapsed: Bool, for id: Int) {
        if isCollapsed {
            guard !collapsed.contains(id) else { return }
            collapsed.insert(id)
        } else {
            guard collapsed.contains(id) else { return }
            collapsed.remove(id)
        }
        persist()
    }

    private func persist() {
        // Keep the persisted set from growing without bound.
        let trimmed = collapsed.count > 2000 ? Set(collapsed.suffix(2000)) : collapsed
        UserDefaults.standard.set(Array(trimmed), forKey: DefaultsKey.collapsed)
    }
}

/// Remembers where the user was scrolled in each story's comments — the ID of
/// the comment row at the top of the viewport, plus the top-level comment it
/// sits under — keyed by story ID, so reopening a thread lands back in the same
/// place. The root is what tells a fresh visit how many pages to load before
/// that row exists.
@Observable
final class CommentScrollStore {
    static let shared = CommentScrollStore()

    struct Position: Equatable {
        let top: Int
        let root: Int
    }

    private var positionByStory: [Int: Position]

    private init() {
        // Stored as [top, root] pairs; anything else (including the pre-paging
        // format, which kept only the top ID) is dropped.
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.scrollPosition) as? [String: [Int]] ?? [:]
        positionByStory = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let id = Int(key), value.count == 2 else { return nil }
            return (id, Position(top: value[0], root: value[1]))
        })
        UserDefaults.standard.removeObject(forKey: DefaultsKey.legacyScrollTop)
    }

    func position(for storyID: Int) -> Position? { positionByStory[storyID] }

    func setPosition(_ position: Position?, for storyID: Int) {
        if let position {
            positionByStory[storyID] = position
        } else {
            positionByStory.removeValue(forKey: storyID)
        }
        persist()
    }

    private func persist() {
        // Keep the persisted map from growing without bound.
        let trimmed = positionByStory.count > 500
            ? Dictionary(uniqueKeysWithValues: positionByStory.suffix(500).map { ($0.key, $0.value) })
            : positionByStory
        let encoded = Dictionary(uniqueKeysWithValues: trimmed.map { (String($0.key), [$0.value.top, $0.value.root]) })
        UserDefaults.standard.set(encoded, forKey: DefaultsKey.scrollPosition)
    }
}

/// User-configurable settings for the points-threshold notifications.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: DefaultsKey.notificationsEnabled) }
    }

    var pointsThreshold: Int {
        didSet { UserDefaults.standard.set(pointsThreshold, forKey: DefaultsKey.pointsThreshold) }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            DefaultsKey.notificationsEnabled: false,
            DefaultsKey.pointsThreshold: 300,
        ])
        notificationsEnabled = defaults.bool(forKey: DefaultsKey.notificationsEnabled)
        pointsThreshold = defaults.integer(forKey: DefaultsKey.pointsThreshold)
    }
}

/// Records which stories have already triggered a notification so we never
/// alert about the same post twice.
enum NotifiedStore {
    static func notifiedIDs() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: DefaultsKey.notified) as? [Int] ?? [])
    }

    static func markNotified(_ ids: Set<Int>) {
        var current = notifiedIDs()
        current.formUnion(ids)
        // Keep the persisted set from growing without bound.
        let trimmed = current.count > 500 ? Set(current.suffix(500)) : current
        UserDefaults.standard.set(Array(trimmed), forKey: DefaultsKey.notified)
    }
}
