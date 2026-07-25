//
//  HackerNewsApp.swift
//  HackerNews
//
//  Created by Elias Floreteng on 2026-06-21.
//

import SwiftUI

@main
struct HackerNewsApp: App {
    @State private var visited = VisitedStore.shared
    @State private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.registerBackgroundTask()
        NotificationManager.registerNotificationDelegate()
    }

    var body: some Scene {
        WindowGroup {
            StoriesView()
                .environment(visited)
                .environment(settings)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            // Queue the next background refresh whenever we go to the background.
            if settings.notificationsEnabled {
                NotificationManager.scheduleRefresh()
            }
            // Get the cache on disk before iOS suspends us and the pending
            // write never happens.
            Task { await ItemCache.shared.flush() }
        }
    }
}
