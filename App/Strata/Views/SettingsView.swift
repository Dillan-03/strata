import AppKit
import SwiftUI
import UserNotifications

enum PreferenceKey {
    static let autoRefresh = "autoRefresh"
}

struct SettingsView: View {
    let notifications: SystemNotifications?
    @AppStorage(PreferenceKey.autoRefresh) private var autoRefresh = true
    @AppStorage(NotificationPreferences.enabledKey) private var notifyAboutChanges = false
    @AppStorage(NotificationPreferences.pausedUntilKey) private var pausedUntil: Double = 0
    @State private var authorization: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                Toggle("Refresh automatically when configuration files change", isOn: $autoRefresh)
                Text(
                    "Strata watches your repositories, ~/.claude and ~/.claude.json, and rescans after edits settle. "
                        + "Claude Code's transcripts and logs are ignored. You can always rescan with ⌘R."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Notifications") {
                Toggle("Notify me when Claude Code configuration changes", isOn: $notifyAboutChanges)
                    .onChange(of: notifyAboutChanges) { _, isOn in
                        guard isOn else { return }
                        Task {
                            _ = await notifications?.requestAuthorization()
                            authorization = await notifications?.authorizationStatus()
                        }
                    }
                if notifyAboutChanges {
                    if authorization == .denied {
                        LabeledContent("macOS has notifications turned off for Strata.") {
                            Button("Open System Settings…") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                    pauseRow
                }
                Text(
                    "Edits that land within a few seconds of each other arrive as one notification, and each change is announced once "
                        + "until you review it. To silence one repository, use its menu in the sidebar."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Privacy") {
                Text("Strata only reads files. It never changes Claude Code configuration, runs MCP servers, or connects to the network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            authorization = await notifications?.authorizationStatus()
        }
    }

    @ViewBuilder private var pauseRow: some View {
        let until = Date(timeIntervalSinceReferenceDate: pausedUntil)
        if until > .now {
            LabeledContent("Paused until \(until.formatted(date: .abbreviated, time: .shortened))") {
                Button("Resume") { pausedUntil = 0 }
            }
        } else {
            LabeledContent("Pause notifications") {
                Menu("Pause") {
                    Button("For 1 Hour") { pausedUntil = Date.now.addingTimeInterval(3600).timeIntervalSinceReferenceDate }
                    Button("Until Tomorrow") {
                        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
                        pausedUntil = tomorrow.timeIntervalSinceReferenceDate
                    }
                }
                .fixedSize()
            }
        }
    }
}
