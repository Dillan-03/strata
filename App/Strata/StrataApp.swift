import SwiftUI

@main
struct StrataApp: App {
    @State private var model = AppModel()

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
