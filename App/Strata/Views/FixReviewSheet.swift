import StrataCore
import SwiftUI

/// Shows exactly what a fix will do and waits for approval. Afterwards it shows what happened, with Undo.
struct FixReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fix: ConfigFix
    let repositoryID: Repository.ID?
    @State private var outcome: FixOutcome?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let outcome {
                    result(outcome)
                } else {
                    review
                }
            }
            footer
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 420, idealHeight: 560)
    }

    // MARK: - Before

    private var review: some View {
        let preview = FixPreview(fix)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fix.title)
                    .font(.title3.weight(.semibold))
                Text("Nothing changes until you confirm.")
                    .foregroundStyle(.secondary)
            }
            section("What Happens") {
                ForEach(steps, id: \.self) { step in
                    Label(step, systemImage: "arrow.right")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            section(fix.action == .replaceWithWinner ? "Replaced" : fix.action.editsJSON ? "Edited" : "Moved to Backups") {
                fileList(preview.targetFiles)
            }
            if fix.action == .replaceWithWinner {
                section("Copied In") { fileList(preview.sourceFiles) }
            }
            if fix.action == .uninstall || fix.action.editsJSON {
                section("In a Running Claude Code Session") { pickup }
            }
            section(fix.action == .replaceWithWinner || fix.action.editsJSON ? "What Changes" : "What Goes") {
                DiffView(diff: preview.diff)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var steps: [String] {
        let target = model.abbreviatingHome(fix.targetURL.path)
        let winner = model.abbreviatingHome(fix.winner?.source.path ?? "")
        var steps: [String]
        switch fix.action {
        case .removeCopy:
            steps = ["Strata moves \(target) into its backups.", "The copy that runs stays where it is: \(winner)."]
        case .replaceWithWinner:
            steps = [
                "Strata copies \(model.abbreviatingHome(fix.sourceURL?.path ?? "")) over \(target).",
                "The old copy goes into Strata's backups first.",
            ]
            if fix.winner?.scope == .user, fix.target.scope == .project {
                steps.append("This puts your personal copy in the repository, so everyone who uses the repository gets it.")
            } else if fix.winner?.scope == .project, fix.target.scope == .user {
                steps.append("This puts the repository's copy in your personal folder, so every repository you open gets it.")
            }
        case .uninstall:
            steps = ["Strata moves \(target) into its backups."]
            let name = fix.target.invocation ?? fix.target.name
            switch fix.overridden.count {
            case 0:
                steps.append("This is the copy that runs, and no other copy takes its place, so \(name) won't be available any more.")
            case 1:
                let next = fix.overridden[0]
                steps.append("This is the copy that runs. Once it's gone, the \(next.scope.title.lowercased()) copy runs instead: \(model.abbreviatingHome(next.source.path)).")
            default:
                steps.append("This is the copy that runs. Once it's gone, one of the \(fix.overridden.count) copies it overrides runs instead. Strata rescans and shows which.")
            }
        case .disablePlugin, .enablePlugin:
            let value = fix.action == .disablePlugin ? "false" : "true"
            steps = [
                "Strata sets \"\(fix.target.name)\": \(value) under enabledPlugins in \(target), and changes nothing else in the file.",
                "A copy of the whole file goes into Strata's backups first.",
                Self.reach(of: fix.target.scope, file: fix.targetURL.lastPathComponent),
            ]
        case .removeServer:
            steps = [
                "Strata removes the \(fix.target.name) entry from \(target), and changes nothing else in the file.",
                "A copy of the whole file goes into Strata's backups first. Strata never starts or contacts the server.",
            ]
            if fix.targetURL.lastPathComponent == ".mcp.json" {
                steps.append("This file is usually committed, so the server goes for everyone who uses the repository once you commit the change.")
            } else {
                steps.append("Claude Code writes this file too. Undo puts back only this entry, so anything Claude Code wrote since is kept.")
            }
        }
        switch fix.action {
        case .replaceWithWinner:
            steps.append("If either copy changes before you confirm, Strata stops and changes nothing. You can undo the fix afterwards.")
        case .disablePlugin, .enablePlugin, .removeServer:
            steps.append("If the file changes before you confirm, Strata stops and changes nothing. You can undo this afterwards.")
        case .removeCopy, .uninstall:
            steps.append("If this copy changes before you confirm, Strata stops and changes nothing. You can undo this afterwards.")
        }
        return steps
    }

    private static func reach(of scope: Scope, file: String) -> String {
        switch scope {
        case .user: "This is your personal settings file, so it applies in every repository."
        case .project: "\(file) is the repository's shared settings, usually committed, so it applies to everyone who uses the repository."
        case .local: "\(file) is your personal settings for this repository only."
        default: "It applies wherever \(file) applies."
        }
    }

    private var pickup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fix.pickup.explanation)
                .fixedSize(horizontal: false, vertical: true)
            if let source = fix.pickup.source {
                Link("Claude Code docs", destination: source)
            }
        }
    }

    // MARK: - After

    private func result(_ outcome: FixOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(outcome.title, systemImage: outcome.isFailure ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(outcome.isFailure ? .red : .green)
            Text(outcome.message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("fixResultMessage")
            if fix.action == .uninstall || fix.action.editsJSON, case .applied = outcome {
                pickup
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            if let outcome {
                if case .applied(let record) = outcome {
                    Button("Undo") {
                        Task {
                            isWorking = true
                            self.outcome = await model.undo(record)
                            isWorking = false
                        }
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("undoFixButton")
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("fixDoneButton")
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(fix.action.confirmTitle, role: .destructive) {
                    guard let repositoryID else { return }
                    Task {
                        isWorking = true
                        outcome = await model.apply(fix, in: repositoryID)
                        isWorking = false
                    }
                }
                .disabled(isWorking || repositoryID == nil)
                .accessibilityIdentifier("confirmFixButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func fileList(_ files: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(files, id: \.self) { file in
                Text(file)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
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

extension ConfigFix {
    var title: String {
        let name = target.invocation ?? target.name
        let scope = target.scope.title.lowercased()
        switch action {
        case .removeCopy: return "Remove the \(scope) copy of \(name)?"
        case .replaceWithWinner: return "Replace the \(scope) copy of \(name) with the \(winner?.scope.title.lowercased() ?? "running") one?"
        case .uninstall: return "Uninstall the \(scope) \(target.kind.title.lowercased()) \(name)?"
        case .disablePlugin: return "Disable the plugin \(target.name)?"
        case .enablePlugin: return "Enable the plugin \(target.name)?"
        case .removeServer: return "Remove the \(scope) MCP server \(target.name)?"
        }
    }
}

extension ConfigFix.Action {
    /// Short, because the inspector is narrow; the sentence above the buttons and the tooltip say the rest.
    var buttonTitle: String {
        switch self {
        case .removeCopy: "Remove…"
        case .replaceWithWinner: "Replace…"
        case .uninstall: "Uninstall…"
        case .disablePlugin: "Disable…"
        case .enablePlugin: "Enable…"
        case .removeServer: "Remove…"
        }
    }

    var confirmTitle: String {
        switch self {
        case .removeCopy: "Remove Copy"
        case .replaceWithWinner: "Replace Copy"
        case .uninstall: "Uninstall"
        case .disablePlugin: "Disable Plugin"
        case .enablePlugin: "Enable Plugin"
        case .removeServer: "Remove Server"
        }
    }

    /// The line above the button in the inspector.
    func inspectorNote(kind: ItemKind) -> String {
        switch self {
        case .removeCopy, .replaceWithWinner, .uninstall:
            "Moves this \(kind.title.lowercased()) into Strata's backups. You'll see exactly what changes first."
        case .disablePlugin:
            "Turns it off in the settings file that turns it on. It stays installed."
        case .enablePlugin:
            "Turns it back on in the settings file that turned it off."
        case .removeServer:
            "Removes its entry and leaves the rest of the file as it is. You'll see exactly what changes first."
        }
    }

    var pastTense: String {
        switch self {
        case .removeCopy: "Removed"
        case .replaceWithWinner: "Replaced"
        case .uninstall: "Uninstalled"
        case .disablePlugin: "Disabled"
        case .enablePlugin: "Enabled"
        case .removeServer: "Removed"
        }
    }
}

extension FixRecord {
    var summary: String {
        "\(action.pastTense) \(itemKind.title.lowercased()) \(itemName) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension FixOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .applied(let record): record.action.pastTense
        case .undone: "Undone"
        case .failed: "The fix didn't run"
        }
    }

    var message: String {
        switch self {
        case .applied:
            "The original is in Strata's backups, and you can undo this here or in Settings. "
                + "A Claude Code session that's already running may keep using the old copy until it reloads."
        case .undone(let record):
            "\(URL(fileURLWithPath: record.targetPath).lastPathComponent) is back as it was."
        case .failed(let reason):
            reason
        }
    }
}
