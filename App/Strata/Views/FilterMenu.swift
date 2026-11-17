import StrataCore
import SwiftUI

/// Toolbar menu for scope, status and issue filters.
struct FilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Section("Scope") {
                ForEach(Scope.allCases, id: \.self) { scope in
                    Toggle(scope.title, isOn: $model.query[scope: scope])
                }
            }
            Section("Status") {
                ForEach(ItemQuery.Status.allCases, id: \.self) { status in
                    Toggle(status.title, isOn: $model.query[status: status])
                }
            }
            Divider()
            Toggle("Only Items with Issues", isOn: $model.query.onlyWithIssues)
            Divider()
            Button("Clear Filters") { model.query.clearFilters() }
                .disabled(!model.query.hasFilters)
        } label: {
            Label("Filter", systemImage: model.query.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(model.query.hasFilters ? "Filters are on" : "Filter by scope and status")
        .accessibilityIdentifier("filterMenu")
    }
}
