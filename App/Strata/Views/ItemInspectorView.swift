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
    @AppStorage(PreferenceKey.allowsFixes) private var allowsFixes = false
    let item: ConfigItem
    let report: InspectionReport
    let formatter: PathFormatter

    var body: some View {
        Form {
            header
            changeSection
            statusSection
            fixSection
            uninstallSection
            pluginUpdateSection
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

    @ViewBuilder private var changeSection: some View {
        if let repositoryID = model.selectedRepositoryID, let pending = model.pendingChange(for: item.id, in: repositoryID) {
            let status = model.syncStatus(of: item.id, in: repositoryID)
            Section("Since Your Last Review") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(status.title, systemImage: status.symbol)
                        .foregroundStyle(status.tint)
                        .fontWeight(.medium)
                    Text(status == .conflict ? model.conflicts(for: pending).first?.title ?? "" : pending.change.pickup.explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Review Change…") { model.review(pending) }
                        .accessibilityIdentifier("reviewItemChangeButton")
                }
            }
        }
    }

    @ViewBuilder private var fixSection: some View {
        switch model.fixOffer(for: item) {
        case .none:
            EmptyView()
        case .unavailable(let reason):
            Section("Fix") {
                Text(reason)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .available(let fixes):
            Section("Fix") {
                if let failure = model.failedFixes[item.id] {
                    Label("The last fix failed: \(failure)", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if allowsFixes {
                    Label("Fix available: this copy never runs", systemImage: "wrench.and.screwdriver")
                    Text(fixes.count > 1
                        ? "Remove it, or replace it with the copy that runs. You'll see exactly what changes first."
                        : "Remove it. You'll see exactly what changes first.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        ForEach(fixes) { fix in
                            Button(fix.action.buttonTitle) { model.proposedFix = fix }
                                .help(fix.title)
                                .accessibilityIdentifier("fix.\(fix.action.rawValue)")
                        }
                    }
                } else {
                    Text("Strata can remove this copy, or replace it with the one that runs. Turn on changes in Settings to use them.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SettingsLink { Text("Open Settings…") }
                }
            }
        }
    }

    /// Uninstalling, turning a plugin off or on, or removing an MCP server. Overridden skills, commands and subagents
    /// are uninstalled with Remove, in the Fix section, so they're left out here.
    @ViewBuilder private var uninstallSection: some View {
        if case .shadowed = item.applicability, FixPlanner.fixableKinds.contains(item.kind) {
            EmptyView()
        } else {
            let offer = model.changeOffer(for: item)
            let command = FixPlanner.uninstallCommand(for: item)
            if offer != .none || command != nil {
                Section(changeSectionTitle) {
                    switch offer {
                    case .none:
                        EmptyView()
                    case .unavailable(let reason):
                        Text(reason)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    case .available(let fixes):
                        if let failure = model.failedFixes[item.id] {
                            Label("The last change failed: \(failure)", systemImage: "xmark.octagon")
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if allowsFixes {
                            ForEach(fixes) { fix in
                                Text(fix.action.inspectorNote(kind: item.kind))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(fix.action.buttonTitle) { model.proposedFix = fix }
                                    .help(fix.title)
                                    .accessibilityIdentifier("fix.\(fix.action.rawValue)")
                            }
                        } else {
                            Text("Strata can make this change. Turn on changes in Settings to use it.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            SettingsLink { Text("Open Settings…") }
                        }
                    }
                    if let command {
                        CommandRow(
                            note: "To uninstall the plugin, run this in Terminal. Strata doesn't run commands.",
                            command: command
                        )
                    }
                }
            }
        }
    }

    /// Versions from the marketplace copy on disk. Strata never fetches; the commands it shows do.
    @ViewBuilder private var pluginUpdateSection: some View {
        if let update = model.pluginUpdate(for: item) {
            Section("Updates") {
                LabeledContent("Installed", value: update.installed ?? "Unknown")
                LabeledContent("In the marketplace copy", value: update.latest ?? "Unknown")
                switch update.status {
                case .upToDate:
                    Label("Up to date with the marketplace copy on this Mac.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pluginUpdateStatus")
                case .available:
                    Label("An update is available.", systemImage: "arrow.down.circle")
                        .accessibilityIdentifier("pluginUpdateStatus")
                    CommandRow(note: "To update, run this in Terminal. It applies after /reload-plugins or in a new session.", command: update.command)
                case .unknown(let reason):
                    Text(reason)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pluginUpdateStatus")
                }
                Button("Check for Plugin Updates…") { model.isCheckingPluginUpdates = true }
            }
        }
    }

    private var changeSectionTitle: String {
        switch item.kind {
        case .plugin: "Plugin"
        case .mcpServer: "Remove"
        default: "Uninstall"
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
        let hooks = item.metadataValue("Hooks")
        Section("Contributes") {
            if components.isEmpty && hooks == nil {
                Text(item.stage == .declared ? "Not installed, so nothing to show." : "No skills, agents, MCP servers or hooks found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(components) { component in
                    relatedButton(component, label: "\(component.kind.title): \(component.invocation ?? component.name)")
                }
                if let hooks {
                    LabeledContent("Hooks", value: hooks)
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
