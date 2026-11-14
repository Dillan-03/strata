import StrataCore
import SwiftUI

struct RepositoryDetailView: View {
    @Environment(AppModel.self) private var model
    let repository: Repository

    var body: some View {
        @Bindable var model = model
        Group {
            if let report = model.reports[repository.id] {
                VStack(spacing: 0) {
                    SummaryBar(report: report)
                    if model.category == .issues {
                        DiagnosticsListView(report: report, formatter: model.pathFormatter(for: repository))
                    } else {
                        ItemListView(report: report, formatter: model.pathFormatter(for: repository))
                    }
                }
            } else {
                ProgressView("Scanning \(repository.displayName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(repository.displayName)
        .navigationSubtitle(repository.url.path)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Category", selection: $model.category) {
                    ForEach(Category.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("categoryPicker")
            }
            ToolbarItem {
                FilterMenu()
            }
            ToolbarItem {
                Button {
                    Task { await model.scan(repository.id) }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan this repository again (⌘R)")
                .disabled(model.isScanning(repository.id))
            }
            ToolbarItem {
                Button {
                    model.isInspectorPresented.toggle()
                } label: {
                    Label(model.isInspectorPresented ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
                }
                .help(model.isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
        }
        .searchable(text: $model.query.text, placement: .toolbar, prompt: "Search")
        .inspector(isPresented: $model.isInspectorPresented) {
            ItemInspectorView(repository: repository)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
        }
        .task(id: repository.id) {
            if model.reports[repository.id] == nil {
                await model.scan(repository.id)
            }
        }
    }
}

/// The strip above the list: issue count and a count per category.
private struct SummaryBar: View {
    @Environment(AppModel.self) private var model
    let report: InspectionReport

    var body: some View {
        let issues = report.diagnostics.filter { $0.severity != .info }
        let applied = report.items.filter { $0.applicability.isApplied }.count
        HStack(spacing: 12) {
            if issues.isEmpty {
                Label("No issues", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    model.category = .issues
                } label: {
                    Label("\(issues.count) item\(issues.count == 1 ? " needs" : "s need") attention", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("issuesSummary")
            }
            Text("\(applied) apply to this repository")
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(countedKinds) { entry in
                Text("\(entry.kind.pluralTitle) \(entry.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private struct KindCount: Identifiable {
        let kind: ItemKind
        let count: Int
        var id: ItemKind { kind }
    }

    private var countedKinds: [KindCount] {
        [ItemKind.skill, .agent, .mcpServer, .plugin, .instruction].compactMap { kind in
            let count = report.items.filter { $0.kind == kind && $0.applicability.isApplied }.count
            return count > 0 ? KindCount(kind: kind, count: count) : nil
        }
    }
}
