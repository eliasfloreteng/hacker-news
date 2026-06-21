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

    private func persist() {
        UserDefaults.standard.set(Array(visited), forKey: DefaultsKey.visited)
    }

    /// Read the visited set directly from defaults (for use off the main actor).
    static func visitedIDs() -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: DefaultsKey.visited) as? [Int] ?? [])
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
