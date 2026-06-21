//
//  NotificationManager.swift
//  HackerNews
//
//  Handles local-notification permission, the BGAppRefreshTask that polls the
//  HN top stories on-device, and the rule that decides what to notify about.
//

import Foundation
import UserNotifications
import BackgroundTasks

enum NotificationManager {
    /// Must match the identifier listed under BGTaskSchedulerPermittedIdentifiers
    /// in Info.plist.
    static let refreshTaskID = "se.floreteng.HackerNews.refresh"

    /// How many of the top stories to inspect on each refresh.
    private static let scanCount = 30

    // MARK: Permission

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Background task lifecycle

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // Earliest the system may run us again; iOS decides the actual timing.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always schedule the next one so the chain continues.
        scheduleRefresh()

        let work = Task {
            let count = await runThresholdCheck()
            task.setTaskCompleted(success: count >= 0)
        }
        task.expirationHandler = { work.cancel() }
    }

    // MARK: Core rule

    /// Scans the current top stories and posts a notification for any whose
    /// score crosses the user's threshold, skipping stories that were already
    /// notified or already visited. Returns the number of notifications posted,
    /// or -1 on failure.
    @discardableResult
    static func runThresholdCheck() async -> Int {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.notificationsEnabled) else { return 0 }
        let threshold = defaults.integer(forKey: DefaultsKey.pointsThreshold)

        do {
            let ids = Array(try await HNClient.shared.topStoryIDs().prefix(scanCount))
            let stories = try await HNClient.shared.items(ids)

            let visited = VisitedStore.visitedIDs()
            let alreadyNotified = NotifiedStore.notifiedIDs()

            let candidates = stories.filter { story in
                (story.score ?? 0) >= threshold
                    && !visited.contains(story.id)
                    && !alreadyNotified.contains(story.id)
                    && !story.isDeadOrDeleted
            }

            for story in candidates {
                await post(story)
            }
            if !candidates.isEmpty {
                NotifiedStore.markNotified(Set(candidates.map(\.id)))
            }
            return candidates.count
        } catch {
            return -1
        }
    }

    private static func post(_ story: HNItem) async {
        let content = UNMutableNotificationContent()
        content.title = "\(story.score ?? 0) points on Hacker News"
        content.body = story.title ?? "New popular story"
        content.sound = .default
        content.userInfo = ["storyID": story.id]

        let request = UNNotificationRequest(
            identifier: "story-\(story.id)",
            content: content,
            trigger: nil // deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
