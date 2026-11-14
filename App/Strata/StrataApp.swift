import SwiftUI

@main
struct StrataApp: App {
    @State private var model: AppModel

    init() {
        let launch = LaunchConfiguration.current()
        let model = AppModel(store: RepositoryStore(defaults: launch.defaults))
        if let repository = launch.initialRepository {
            model.add(repository)
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup("Strata") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Repository…") {
                    model.presentAddRepositoryPanel()
                }
                .keyboardShortcut("o")
            }
        }
    }
}
