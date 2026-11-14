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
            header
            statusSection
            whySection
            definitionsSection
            kindSpecificSections
            sourceSection
            detailsSection
            issuesSection
            Section {
                Text("Strata reads files on disk. It can't see what a running Claude Code session has loaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("itemInspector")
    }

    // MARK: - Common sections

    private var header: some View {
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
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Status") { StatusBadge(applicability: item.applicability) }
            if item.kind == .plugin {
                LabeledContent("Stage", value: item.stage.title)
            }
            LabeledContent("Loads", value: item.loadTiming.title)
        }
    }

    private var whySection: some View {
        Section("Why") {
            ForEach(Array(item.explanation.enumerated()), id: \.offset) { _, sentence in
                Text(sentence)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Which copy runs": every definition competing for this name, best first.
    @ViewBuilder private var definitionsSection: some View {
        let definitions = report.definitions(competingWith: item)
        if definitions.count > 1, item.kind != .instruction, item.kind != .plugin {
            Section(item.kind == .setting ? "Where It's Set" : "Which Copy Runs") {
                ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                    Button {
                        model.reveal(definition.id)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 16, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(definition.kind == .command ? "\(definition.scope.title) command" : definition.scope.title)
                                Text(formatter.display(definition.source.path))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            StatusBadge(applicability: definition.applicability)
                        }
                        .fontWeight(definition.id == item.id ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .disabled(definition.id == item.id)
                    .accessibilityLabel("\(definition.scope.title) definition, \(definition.applicability.title)")
                }
            }
        }
    }

    @ViewBuilder private var kindSpecificSections: some View {
        switch item.kind {
        case .plugin:
            pluginSections
        case .instruction:
            instructionSections
        case .mcpServer:
            Section {
                Label("Strata never runs this command or connects to this server. Secrets are masked.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
        if let plugin = report.plugin(providing: item) {
            Section("From Plugin") {
                relatedButton(plugin, label: plugin.name)
            }
        }
    }

    private var sourceSection: some View {
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
            if let origin = item.origin, item.scope != .plugin {
                LabeledContent("From", value: origin)
            }
            HStack {
                Button("Reveal in Finder") { model.revealInFinder(item.source.url) }
                Button("Open") { model.open(item.source.url) }
                    .disabled(!FileManager.default.fileExists(atPath: item.source.path))
            }
        }
    }

    @ViewBuilder private var detailsSection: some View {
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
    }

    @ViewBuilder private var issuesSection: some View {
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
    }

    // MARK: - Plugins

    @ViewBuilder private var pluginSections: some View {
        let components = report.components(ofPlugin: item)
        Section("Contributes") {
            if components.isEmpty {
                Text(item.stage == .declared ? "Not installed, so nothing to show." : "No skills, agents or MCP servers found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(components) { component in
                    relatedButton(component, label: "\(component.kind.title): \(component.invocation ?? component.name)")
                }
            }
        }
    }

    // MARK: - Instructions

    @ViewBuilder private var instructionSections: some View {
        let imports = report.imports(of: item)
        if !imports.isEmpty {
            Section("Imports") {
                ForEach(imports) { imported in
                    relatedButton(imported, label: imported.name)
                }
            }
        }
        let launch = report.launchInstructions
        if launch.contains(where: { $0.id == item.id }) {
            Section("Load Order at Session Start") {
                ForEach(Array(launch.enumerated()), id: \.element.id) { index, file in
                    HStack {
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .leading)
                        Text(file.name)
                            .font(.callout.monospaced())
                            .fontWeight(file.id == item.id ? .semibold : .regular)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Later files sit closer to the end of Claude's context. Nothing is overridden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relatedButton(_ other: ConfigItem, label: String) -> some View {
        Button {
            model.reveal(other.id)
        } label: {
            HStack {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                StatusBadge(applicability: other.applicability)
            }
        }
        .buttonStyle(.plain)
    }
}
