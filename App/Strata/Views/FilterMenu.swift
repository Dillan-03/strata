import StrataCore
import SwiftUI

/// Toolbar menu for scope, status and issue filters.
struct FilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("Scope") {
                ForEach(Scope.allCases, id: \.self) { scope in
                    Toggle(scope.title, isOn: binding(for: scope))
                }
            }
            Section("Status") {
                ForEach(ItemQuery.Status.allCases, id: \.self) { status in
                    Toggle(status.title, isOn: binding(for: status))
                }
            }
            Divider()
            Toggle("Only Items with Issues", isOn: onlyWithIssues)
            Divider()
            Button("Clear Filters") { model.query.clearFilters() }
                .disabled(!model.query.hasFilters)
        } label: {
            Label("Filter", systemImage: model.query.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(model.query.hasFilters ? "Filters are on" : "Filter by scope and status")
        .accessibilityIdentifier("filterMenu")
    }

    private func binding(for scope: Scope) -> Binding<Bool> {
        Binding {
            model.query.scopes.contains(scope)
        } set: { isOn in
            if isOn { model.query.scopes.insert(scope) } else { model.query.scopes.remove(scope) }
        }
    }

    private func binding(for status: ItemQuery.Status) -> Binding<Bool> {
        Binding {
            model.query.statuses.contains(status)
        } set: { isOn in
            if isOn { model.query.statuses.insert(status) } else { model.query.statuses.remove(status) }
        }
    }

    private var onlyWithIssues: Binding<Bool> {
        Binding {
            model.query.onlyWithIssues
        } set: {
            model.query.onlyWithIssues = $0
        }
    }
}
