import StrataCore
import SwiftUI

@main
struct StrataApp: App {
    @State private var model: AppModel

    init() {
        let launch = LaunchConfiguration.current()
        let environment: ScanEnvironment
        if let home = launch.homeOverride {
            environment = ScanEnvironment(homeDirectory: home, managedDirectory: nil)
        } else {
            environment = .current()
        }
        let model = AppModel(store: RepositoryStore(defaults: launch.defaults), environment: environment)
        if let repository = launch.initialRepository {
            model.add(repository)
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup("Strata") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
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

                Divider()

                ForEach(Category.allCases) { category in
                    Button(category.title) { model.category = category }
                        .keyboardShortcut(category.shortcut, modifiers: .command)
                }
            }
        }
    }
}
