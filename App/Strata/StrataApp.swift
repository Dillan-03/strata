import StrataCore
import SwiftUI

@main
struct StrataApp: App {
    @State private var model: AppModel
    /// Kept alive for the app's lifetime: it's the notification centre's delegate, which only holds it weakly.
    private let notifications: SystemNotifications?
    /// Settings read with @AppStorage come from here too, so UI tests keep theirs in a throwaway domain.
    private let defaults: UserDefaults

    init() {
        let launch = LaunchConfiguration.current()
        let environment: ScanEnvironment
        if let home = launch.homeOverride {
            environment = ScanEnvironment(homeDirectory: home, managedDirectory: nil)
        } else {
            environment = .current()
        }
        defaults = launch.defaults
        let model = AppModel(store: RepositoryStore(defaults: launch.defaults), environment: environment)
        launch.initialRepositories.forEach(model.add)
        model.selectedRepositoryID = model.repositories.first?.id
        if launch.isUITesting || launch.isHostingUnitTests {
            notifications = nil
        } else {
            let notifications = SystemNotifications()
            notifications.onOpen = { [weak model] in model?.isReviewingChanges = true }
            model.announcer = notifications
            self.notifications = notifications
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup("Strata") {
            ContentView()
                .environment(model)
                .defaultAppStorage(defaults)
                .frame(minWidth: 960, minHeight: 600)
                .task { await model.checkForUpdatesIfDue(defaults: defaults) }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Repository…") {
                    model.presentAddRepositoryPanel()
                }
                .keyboardShortcut("o")
            }
            CommandMenu("Inspect") {
                Button("Rescan") {
                    Task { await model.scanSelectedRepository() }
                }
                .keyboardShortcut("r")
                .disabled(model.selectedRepository == nil)

                Button("Review Changes…") {
                    model.isReviewingChanges = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.pendingChanges.isEmpty)

                Button("Check for Plugin Updates…") {
                    model.isCheckingPluginUpdates = true
                }
                .disabled(model.selectedReport == nil)

                Button("Export Report…") {
                    model.isExportingReport = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedReport == nil)

                Divider()

                ForEach(Category.allCases) { category in
                    Button(category.title) { model.category = category }
                        .keyboardShortcut(category.shortcut, modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(notifications: notifications)
                .environment(model)
                .defaultAppStorage(defaults)
        }
    }
}
