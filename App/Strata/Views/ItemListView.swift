import StrataCore
import SwiftUI

struct ItemListView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.allowsFixes) private var allowsFixes = false
    let report: InspectionReport
    let formatter: PathFormatter

    var body: some View {
        @Bindable var model = model
        let groups = Self.groups(model.visibleItems)
        if groups.isEmpty, !model.query.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "magnifyingglass")
            } description: {
                Text(model.query.text.isEmpty ? "No items match the current filters." : "No items match “\(model.query.text)” with the current filters.")
            } actions: {
                if model.query.hasFilters {
                    Button("Clear Filters") { model.query.clearFilters() }
                }
            }
        } else if groups.isEmpty {
            ContentUnavailableView {
                Label("Nothing Here", systemImage: "tray")
            } description: {
                Text(report.hasRepositoryConfiguration || !report.items.isEmpty
                    ? "No \(model.category.title.lowercased()) apply to this repository."
                    : "This repository has no Claude Code configuration, and nothing global was found.")
            }
        } else {
            List(selection: $model.selectedItemID) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            ItemRow(
                                item: item,
                                formatter: formatter,
                                syncStatus: model.selectedRepositoryID.map { model.syncStatus(of: item.id, in: $0) } ?? .unchanged
                            )
                            .tag(item.id)
                            .contextMenu {
                                if allowsFixes, FixPlanner.fixableKinds.contains(item.kind), FixPlanner.writableScopes.contains(item.scope) {
                                    Button("Uninstall…") { model.proposeUninstall(item) }
                                }
                            }
                        }
                    } header: {
                        Text("\(group.kind.pluralTitle) (\(group.items.count))")
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .accessibilityIdentifier("itemList")
        }
    }

    struct Group: Identifiable {
        let kind: ItemKind
        let items: [ConfigItem]
        var id: ItemKind { kind }
    }

    static func groups(_ items: [ConfigItem]) -> [Group] {
        ItemKind.allCases.compactMap { kind in
            let matching = items.filter { $0.kind == kind }
            return matching.isEmpty ? nil : Group(kind: kind, items: matching)
        }
    }
}

struct ItemRow: View {
    let item: ConfigItem
    let formatter: PathFormatter
    var syncStatus: SyncStatus = .unchanged

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.invocation ?? item.name)
                    .font(item.kind == .instruction ? .body : .body.monospaced())
                    .strikethrough(isStruckThrough)
                    .foregroundStyle(item.applicability.isApplied || item.applicability == .conditional ? .primary : .secondary)
                    .truncationMode(.middle)
                if let summary = item.summary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("\(item.scope.title) · \(formatter.display(item.source.path))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if syncStatus != .unchanged {
                SyncTag(status: syncStatus)
                    .fixedSize()
            }
            StatusBadge(applicability: item.applicability)
                .fixedSize()
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("itemRow.\(item.kind.rawValue).\(item.scope.rawValue).\(item.name)")
    }

    private var accessibilityText: String {
        let base = "\(item.invocation ?? item.name), \(item.kind.title), \(item.scope.title), \(item.applicability.title)"
        return syncStatus == .unchanged ? base : "\(base), \(syncStatus.title)"
    }

    private var isStruckThrough: Bool {
        if case .shadowed = item.applicability { return true }
        return false
    }
}
