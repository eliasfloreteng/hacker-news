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
    }

    var body: some Scene {
        WindowGroup {
            StoriesView()
                .environment(visited)
                .environment(settings)
        }
        .onChange(of: scenePhase) { _, phase in
            // Queue the next background refresh whenever we go to the background.
            if phase == .background, settings.notificationsEnabled {
                NotificationManager.scheduleRefresh()
            }
        }
    }
}
