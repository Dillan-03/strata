import StrataCore
import SwiftUI

struct ItemInspectorView: View {
    @Environment(AppModel.self) private var model
    let repository: Repository

    var body: some View {
        if let item = model.selectedItem, let report = model.reports[repository.id] {
            ItemDetail(item: item, report: report, formatter: model.pathFormatter(for: repository))
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right", description: Text("Select an item to see where it comes from and why it applies."))
        }
    }
}

private struct ItemDetail: View {
    @Environment(AppModel.self) private var model
    let item: ConfigItem
    let report: InspectionReport
    let formatter: PathFormatter

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.invocation ?? item.name)
                        .font(.title3.weight(.semibold).monospaced())
                        .textSelection(.enabled)
                    if let summary = item.summary {
                        Text(summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Status") {
                LabeledContent("Status") { StatusBadge(applicability: item.applicability) }
                if item.kind == .plugin {
                    LabeledContent("Stage", value: item.stage.title)
                }
                LabeledContent("Loads", value: item.loadTiming.title)
                if let rank = item.precedenceRank, competitors.count > 1 {
                    LabeledContent("Precedence", value: "\(rank) of \(competitors.count)")
                }
            }

            Section("Why") {
                ForEach(Array(item.explanation.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if case .shadowed(let winnerID) = item.applicability, let winner = report.item(withID: winnerID) {
                Section("Overridden By") {
                    relatedButton(winner)
                }
            }

            if !overridden.isEmpty {
                Section("Overrides") {
                    ForEach(overridden) { relatedButton($0) }
                }
            }

            Section("Source") {
                LabeledContent("Scope", value: item.scope.title)
                LabeledContent("File") {
                    Text(formatter.display(item.source.path))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if let keyPath = item.source.keyPath {
                    LabeledContent("Key", value: keyPath)
                }
                if let origin = item.origin {
                    LabeledContent(item.scope == .plugin ? "Plugin" : "From", value: origin)
                }
                HStack {
                    Button("Reveal in Finder") { model.revealInFinder(item.source.url) }
                    Button("Open") { model.open(item.source.url) }
                        .disabled(!FileManager.default.fileExists(atPath: item.source.path))
                }
            }

            if !item.metadata.isEmpty {
                Section("Details") {
                    ForEach(Array(item.metadata.enumerated()), id: \.offset) { _, entry in
                        LabeledContent(entry.label) {
                            Text(entry.value)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }

            let diagnostics = report.diagnostics(for: item.id)
            if !diagnostics.isEmpty {
                Section("Issues") {
                    ForEach(diagnostics) { diagnostic in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.title)
                                if let suggestion = diagnostic.suggestion {
                                    Text(suggestion).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            SeverityIcon(severity: diagnostic.severity)
                        }
                    }
                }
            }

            Section {
                Text("Strata reads files on disk. It can't see what a running Claude Code session has loaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("itemInspector")
    }

    private var competitors: [ConfigItem] {
        report.items.filter { $0.kind == item.kind && $0.name == item.name && $0.precedenceRank != nil }
    }

    private var overridden: [ConfigItem] {
        report.items.filter { other in
            if case .shadowed(let winner) = other.applicability { return winner == item.id }
            return false
        }
    }

    private func relatedButton(_ other: ConfigItem) -> some View {
        Button {
            model.reveal(other.id)
        } label: {
            LabeledContent(other.scope.title) {
                Text(formatter.display(other.source.path))
                    .font(.callout.monospaced())
            }
        }
        .buttonStyle(.plain)
    }
}
