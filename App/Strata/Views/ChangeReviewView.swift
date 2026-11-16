import AppKit
import StrataCore
import SwiftUI

/// The strip that appears under the summary when Claude Code configuration reaching this repository has changed.
struct ChangeBanner: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("Review Changes…") {
                model.isReviewingChanges = true
            }
            .accessibilityIdentifier("reviewChangesButton")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("changeBanner")
    }

    private var title: String {
        let changes = "\(count) configuration change\(count == 1 ? "" : "s")"
        guard let since = model.changesSince else { return changes }
        return "\(changes) since \(since.formatted(date: .omitted, time: .shortened))"
    }
}

/// Everything that changed since the last review: one list across repositories, each change with its diff,
/// where it reaches, when a running session sees it, conflicts and security notes.
struct ChangeReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PendingChange.ID?

    var body: some View {
        VStack(spacing: 0) {
            if model.pendingChanges.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing in your Claude Code configuration has changed since the last review.")
                )
            } else {
                HStack(spacing: 0) {
                    changeList
                        .frame(width: 300)
                    Divider()
                    if let pending = model.pendingChanges.first(where: { $0.id == selection }) {
                        ChangeDetail(pending: pending)
                            .id(pending.id)
                    } else {
                        ContentUnavailableView("No Selection", systemImage: "sidebar.left", description: Text("Select a change to see what's different."))
                    }
                }
            }
            footer
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 460, idealHeight: 620)
        .onAppear {
            let selected = model.selectedRepositoryID.map { model.changes(reaching: $0) } ?? []
            selection = selected.first?.id ?? model.pendingChanges.first?.id
        }
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Changes")
                    .font(.headline)
                Text(counts)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.changes) { pending in
                            ChangeRow(change: pending.change, isSelected: pending.id == selection)
                                .tag(pending.id)
                        }
                    }
                }
            }
            .accessibilityIdentifier("changeList")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Strata compares files on disk between scans. It can't see what a running Claude Code session has loaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Mark All as Reviewed") {
                model.markChangesReviewed()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.pendingChanges.isEmpty)
            .help("Start comparing from the configuration as it is now")
            .accessibilityIdentifier("markReviewedButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var counts: String {
        let kinds: [(ConfigChange.Kind, String)] = [(.created, "added"), (.updated, "changed"), (.deleted, "removed"), (.renamed, "moved")]
        return kinds.compactMap { kind, word in
            let count = model.pendingChanges.filter { $0.change.kind == kind }.count
            return count > 0 ? "\(count) \(word)" : nil
        }
        .joined(separator: " · ")
    }

    private struct ChangeGroup: Identifiable {
        let id: String
        let title: String
        let changes: [PendingChange]
    }

    /// Global changes first, then parent-folder ones, then each repository's own, in sidebar order.
    private var groups: [ChangeGroup] {
        var groups: [ChangeGroup] = []
        let global = model.pendingChanges.filter { $0.change.reach == .global }
        if !global.isEmpty { groups.append(ChangeGroup(id: "global", title: "Global", changes: global)) }
        let shared = model.pendingChanges.filter { $0.change.reach == .shared }
        if !shared.isEmpty { groups.append(ChangeGroup(id: "shared", title: "Parent Folders", changes: shared)) }
        for repository in model.repositories {
            let own = model.pendingChanges.filter { $0.change.reach == .repository && $0.repositoryIDs.first == repository.id }
            if !own.isEmpty { groups.append(ChangeGroup(id: repository.id.uuidString, title: repository.displayName, changes: own)) }
        }
        return groups
    }
}

private struct ChangeRow: View {
    let change: ConfigChange
    /// The kind's colour loses contrast against the selection, so a selected row's icon follows its text instead.
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: change.kind.symbol)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(change.kind.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.item.invocation ?? change.item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(change.item.kind.title) · \(change.item.scope.title) · \(change.kind.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("changeRow.\(change.kind.rawValue).\(change.item.name)")
    }
}

private struct ChangeDetail: View {
    @Environment(AppModel.self) private var model
    let pending: PendingChange

    private var change: ConfigChange { pending.change }

    var body: some View {
        let diff = ConfigDiff(change)
        let notes = SecurityReview.notes(for: change)
        let conflicts = model.conflicts(for: pending)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                section("When Claude Code Sees It") { pickup }
                section("Where It Reaches") { reach }
                if !conflicts.isEmpty {
                    section("Conflicts") {
                        ForEach(conflicts) { diagnostic in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diagnostic.title)
                                    Text(diagnostic.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } icon: {
                                SeverityIcon(severity: diagnostic.severity)
                            }
                        }
                    }
                }
                if !notes.isEmpty {
                    section("Security") {
                        ForEach(notes) { note in
                            SecurityNoteRow(note: note)
                        }
                    }
                    .accessibilityIdentifier("securityNotes")
                }
                section(diffTitle(diff)) { DiffView(diff: diff) }
                section("Prompt for Claude Code") {
                    PromptPreview(prompt: model.updatePrompt(for: pending), beforePasting: UpdatePrompt.beforePasting(change))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(change.item.kind.title) · \(change.item.scope.title)".uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(change.item.invocation ?? change.item.name)
                .font(.title3.weight(.semibold).monospaced())
                .textSelection(.enabled)
            Text(location)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                CopyPromptButton(prompt: model.updatePrompt(for: pending))
                if change.kind != .deleted {
                    Group {
                        Button("Reveal in Finder") { model.revealInFinder(change.item.source.url) }
                        Button("Open") { model.open(change.item.source.url) }
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    private var location: String {
        let path = model.abbreviatingHome(change.item.source.path)
        let key = change.item.source.keyPath.map { " → \($0)" } ?? ""
        switch change.kind {
        case .created: return "Added in \(path)\(key)"
        case .updated: return "Changed in \(path)\(key)"
        case .deleted: return "Removed from \(path)\(key)"
        case .renamed:
            let from = change.previous.map { model.abbreviatingHome($0.source.path) } ?? "an earlier location"
            return "Moved from \(from) to \(path)"
        }
    }

    private var pickup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(change.pickup.timing.title, systemImage: change.pickup.timing.symbol)
                .fontWeight(.medium)
            Text(change.pickup.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let source = change.pickup.source {
                Link("Claude Code docs", destination: source)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder private var reach: some View {
        if change.reach == .repository {
            let names = pending.repositoryIDs.compactMap { id in model.repositories.first { $0.id == id }?.displayName }
            Text("Only \(names.joined(separator: ", ")). Repository configuration doesn't reach other repositories.")
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let impacts = model.impacts(of: change)
            if impacts.isEmpty {
                Text("No repository Strata has scanned is affected.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(impacts) { entry in
                        ImpactRow(name: entry.repository.displayName, effect: entry.impact.effect)
                    }
                }
            }
        }
    }

    private func diffTitle(_ diff: ConfigDiff) -> String {
        switch (change.kind, diff) {
        case (.created, .text): return "New File"
        case (.deleted, .text): return "Removed File"
        case (_, .text(let text)): return "What Changed  +\(text.addedCount) −\(text.removedCount)"
        case (.created, _): return "New Entry"
        case (.deleted, _): return "Removed Entry"
        default: return "What Changed"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

/// Copies the update prompt. It only ever goes to the clipboard: pasting it into Claude Code is the user's move.
private struct CopyPromptButton: View {
    let prompt: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy Prompt for Claude Code", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .help("Copy a message that tells a running Claude Code session about this change")
        .accessibilityIdentifier("copyPromptButton")
    }
}

private struct PromptPreview: View {
    let prompt: String
    let beforePasting: String?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste it into the Claude Code session you have open, so it knows what changed. Strata never sends it anywhere.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let beforePasting {
                Label(beforePasting, systemImage: "arrow.clockwise")
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                CopyPromptButton(prompt: prompt)
                Button(isExpanded ? "Hide the Prompt" : "Show the Prompt") { isExpanded.toggle() }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("togglePromptButton")
            }
            if isExpanded {
                Text(prompt)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("promptText")
            }
        }
    }
}

private struct ImpactRow: View {
    let name: String
    let effect: RepositoryImpact.Effect

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(name)
                .fontWeight(.medium)
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch effect {
        case .affected: "checkmark.circle.fill"
        case .possiblyAffected: "questionmark.circle"
        case .shadowed: "eye.slash"
        case .unaffected: "minus.circle"
        }
    }

    private var tint: Color {
        switch effect {
        case .affected: .green
        case .possiblyAffected: .blue
        case .shadowed: .orange
        case .unaffected: .secondary
        }
    }

    private var description: String {
        switch effect {
        case .affected: "Changes what Claude Code uses here."
        case .possiblyAffected: "May change it: it applies only under a condition, or Strata can't tell."
        case .shadowed(let winner): "No effect: the \(winner.scope.title.lowercased()) copy wins here."
        case .unaffected: "Not affected."
        }
    }
}

private struct SecurityNoteRow: View {
    let note: SecurityNote

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = note.source {
                    Link("Claude Code docs", destination: source)
                        .font(.callout)
                }
            }
        } icon: {
            Image(systemName: note.level == .caution ? "exclamationmark.shield.fill" : "info.circle")
                .foregroundStyle(note.level == .caution ? .orange : .secondary)
                .accessibilityLabel(note.level == .caution ? "Caution" : "Note")
        }
    }
}

extension ConfigChange.Kind {
    var title: String {
        switch self {
        case .created: "Added"
        case .updated: "Changed"
        case .deleted: "Removed"
        case .renamed: "Moved"
        }
    }

    var symbol: String {
        switch self {
        case .created: "plus.circle.fill"
        case .updated: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .created: .green
        case .updated: .blue
        case .deleted: .red
        case .renamed: .purple
        }
    }
}

extension SessionPickup.Timing {
    var title: String {
        switch self {
        case .live: "Picked up automatically"
        case .onDemand: "Loads when it's next needed"
        case .reloadSkills: "Run /reload-skills"
        case .reloadPlugins: "Run /reload-plugins"
        case .nextSession: "Needs a new session"
        case .unknown: "Not documented: start a new session to be sure"
        }
    }

    var symbol: String {
        switch self {
        case .live: "bolt.fill"
        case .onDemand: "clock"
        case .reloadSkills, .reloadPlugins: "arrow.clockwise"
        case .nextSession: "arrow.counterclockwise.circle"
        case .unknown: "questionmark.circle"
        }
    }
}
