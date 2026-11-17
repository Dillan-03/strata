import AppKit
import SwiftUI
import UserNotifications

enum PreferenceKey {
    static let autoRefresh = "autoRefresh"
    /// Off by default: Strata only reads configuration until this is turned on.
    static let allowsFixes = "allowsFixes"
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let notifications: SystemNotifications?
    @AppStorage(PreferenceKey.allowsFixes) private var allowsFixes = false
    @State private var undoOutcome: FixOutcome?
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
            Section("Changes") {
                Toggle("Let Strata change Claude Code configuration when you approve", isOn: $allowsFixes)
                    .accessibilityIdentifier("allowsFixesToggle")
                Text(
                    "Off by default. When it's on, Strata can uninstall a skill, command or subagent, remove an overridden copy or "
                        + "replace it with the copy that runs, disable or enable a plugin, and remove an MCP server. It only edits "
                        + "~/.claude, ~/.claude.json, and a repository's .claude folder and .mcp.json. Every change shows you what it "
                        + "will do first, keeps a backup, and can be undone here."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.fixRecords.prefix(10)) { record in
                    LabeledContent {
                        if record.undoneAt == nil {
                            Button("Undo") { Task { undoOutcome = await model.undo(record) } }
                        } else {
                            Text("Undone").foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(record.summary)
                        Text(model.abbreviatingHome(record.targetPath))
                    }
                }
                if !model.fixRecords.isEmpty {
                    Button("Show Backups in Finder") { model.revealInFinder(model.fixBackupDirectory) }
                }
            }
            AboutSection()
            Section("Privacy") {
                Text(
                    "Strata only reads files unless you turn on changes, and then it only changes what you approve. "
                        + "It never runs MCP servers. Its only network request is Check for Updates, one request to GitHub "
                        + "made only when you click it."
                )
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
            model.reloadFixRecords()
        }
        .alert(undoOutcome?.title ?? "", isPresented: Binding(get: { undoOutcome != nil }, set: { if !$0 { undoOutcome = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(undoOutcome?.message ?? "")
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
