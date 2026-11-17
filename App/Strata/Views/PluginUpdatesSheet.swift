import AppKit
import StrataCore
import SwiftUI

/// Plugin versions against the marketplace copies on this Mac, and the Claude Code commands that refresh and update them.
/// Strata never runs those commands or contacts a marketplace; it rescans when the commands change files.
struct PluginUpdatesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plugins = (model.selectedReport?.items ?? []).filter { $0.kind == .plugin }
        let updates = plugins.compactMap { plugin in model.pluginUpdate(for: plugin).map { (plugin, $0) } }
        let available = updates.filter { $0.1.status == .available }
        VStack(spacing: 0) {
            Form {
                Section("1. Refresh the Marketplaces") {
                    Text(
                        "Strata compares against the marketplace copies Claude Code keeps on this Mac. To fetch the latest listings, "
                            + "run this in Terminal. It contacts the sources below; Strata doesn't."
                    )
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.marketplaces, id: \.name) { marketplace in
                        LabeledContent(marketplace.name, value: marketplace.source)
                    }
                    CommandRow(command: PluginUpdates.refreshCommand)
                }
                Section("2. Update Plugins") {
                    if updates.isEmpty {
                        Text("No plugins in this repository come from a marketplace.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(updates, id: \.0.id) { plugin, update in
                        row(plugin, update)
                    }
                    if available.count > 1 {
                        Button("Copy All Update Commands") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(available.map(\.1.command).joined(separator: "\n"), forType: .string)
                        }
                        .help("Claude Code has no command that updates every plugin, so this copies one command per plugin.")
                    }
                    Text("Updates apply after /reload-plugins or in a new session. Review Changes shows what each one changed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 560)
    }

    @ViewBuilder private func row(_ plugin: ConfigItem, _ update: PluginUpdate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(plugin.name) {
                switch update.status {
                case .upToDate: Text("\(update.installed ?? "") · up to date").foregroundStyle(.secondary)
                case .available: Text("\(update.installed ?? "unknown") → \(update.latest ?? "")")
                case .unknown: Text(update.installed ?? "Unknown").foregroundStyle(.secondary)
                }
            }
            switch update.status {
            case .available: CommandRow(command: update.command)
            case .unknown(let reason): Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .upToDate: EmptyView()
            }
        }
        .accessibilityIdentifier("pluginUpdateRow.\(plugin.name)")
    }
}
