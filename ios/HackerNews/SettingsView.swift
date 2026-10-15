//
//  SettingsView.swift
//  HackerNews
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var permissionDenied = false
    @State private var checkResult: String?

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("Hide points", isOn: $settings.hidePoints)
                    Toggle("Hide author", isOn: $settings.hideAuthor)
                    Toggle("Hide comment counts", isOn: $settings.hideComments)
                } header: {
                    Text("Story list")
                } footer: {
                    Text("Read stories on their titles alone, without the crowd's numbers next to them. The comments button stays at the right of each story. Hiding all three fits more stories on screen.")
                }

                Section {
                    Toggle("Highlight popular stories", isOn: $settings.highlightEnabled)

                    Stepper(value: $settings.highlightThreshold, in: 100...3000, step: 100) {
                        HStack {
                            Text("Points threshold")
                            Spacer()
                            Text("\(settings.highlightThreshold)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .disabled(!settings.highlightEnabled)
                } footer: {
                    Text("Marks stories at or above the threshold with a small orange flame, even when points are hidden.")
                }

                Section {
                    Toggle("Notify on popular stories", isOn: $settings.notificationsEnabled)
                        .onChange(of: settings.notificationsEnabled) { _, enabled in
                            if enabled { Task { await enableNotifications() } }
                        }

                    Stepper(value: $settings.pointsThreshold, in: 50...2000, step: 50) {
                        HStack {
                            Text("Points threshold")
                            Spacer()
                            Text("\(settings.pointsThreshold)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .disabled(!settings.notificationsEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Sends a local notification when a top story crosses the threshold. Stories you've already opened are never notified. The app checks periodically in the background; exact timing is controlled by iOS.")
                }

                if permissionDenied {
                    Section {
                        Label("Notifications are disabled in iOS Settings.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Section {
                    Button("Check for popular stories now") {
                        Task {
                            let count = await NotificationManager.runThresholdCheck()
                            checkResult = count < 0
                                ? "Check failed — try again."
                                : "Found \(count) new \(count == 1 ? "story" : "stories") to notify about."
                        }
                    }
                    .disabled(!settings.notificationsEnabled)
                    if let result = checkResult {
                        Text(result).font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Runs the same check the background task performs, so you can verify it without waiting for iOS to schedule a refresh.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func enableNotifications() async {
        let granted = await NotificationManager.requestAuthorization()
        permissionDenied = !granted
        if granted {
            NotificationManager.scheduleRefresh()
        } else {
            settings.notificationsEnabled = false
        }
    }
}
