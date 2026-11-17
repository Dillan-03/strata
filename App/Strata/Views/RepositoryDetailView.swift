import StrataCore
import SwiftUI

struct RepositoryDetailView: View {
    // Narrower than this, the eight-segment category picker pushes itself and the toolbar's buttons into the » overflow menu.
    // ponytail: an estimate from the picker's width plus the sidebar, title and buttons. A long repository name can
    // still overflow just above it, and a hidden sidebar leaves room it doesn't use. Measure the toolbar if that matters.
    static let segmentedPickerWindowWidth: CGFloat = 1200

    @Environment(AppModel.self) private var model
    let repository: Repository
    /// Shows the category picker as a pop-up so the toolbar's other items stay visible.
    var compactToolbar = false

    var body: some View {
        @Bindable var model = model
        Group {
            if let report = model.reports[repository.id] {
                VStack(spacing: 0) {
                    SummaryBar(report: report)
                    let changes = model.changes(reaching: repository.id).count
                    if changes > 0 {
                        ChangeBanner(count: changes)
                    }
                    if model.category == .issues {
                        DiagnosticsListView(report: report, formatter: model.pathFormatter(for: repository))
                    } else {
                        FilterChips(items: model.categoryItems, report: report)
                        ItemListView(report: report, formatter: model.pathFormatter(for: repository))
                    }
                }
            } else {
                ProgressView("Scanning \(repository.displayName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(repository.displayName)
        .navigationSubtitle(model.pathFormatter(for: repository).abbreviatingHome(repository.url.standardizedFileURL.path))
        .toolbar {
            ToolbarItem(placement: .principal) {
                let picker = Picker("Category", selection: $model.category) {
                    ForEach(Category.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                Group {
                    if compactToolbar {
                        picker.pickerStyle(.menu).fixedSize()
                    } else {
                        picker.pickerStyle(.segmented)
                    }
                }
                .labelsHidden()
                .help("Category (⌘1 to ⌘8)")
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                issueStatus(issues.count)
                Text("\(applied) apply to this repository").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                ForEach(countedKinds) { entry in
                    Text("\(entry.kind.pluralTitle) \(entry.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                issueStatus(issues.count)
                Text("\(applied) apply").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack {
                issueStatus(issues.count)
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func issueStatus(_ count: Int) -> some View {
        if count == 0 {
            Label("No issues", systemImage: "checkmark.seal")
                .foregroundStyle(.secondary)
        } else {
            Button {
                model.category = .issues
            } label: {
                Label("\(count) item\(count == 1 ? " needs" : "s need") attention", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("issuesSummary")
        }
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
