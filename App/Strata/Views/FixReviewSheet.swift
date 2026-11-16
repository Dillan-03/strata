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
            section(fix.action == .removeCopy ? "Moved to Backups" : "Replaced") {
                fileList(preview.targetFiles)
            }
            if fix.action == .replaceWithWinner {
                section("Copied In") { fileList(preview.sourceFiles) }
            }
            section(fix.action == .removeCopy ? "What Goes" : "How the Main File Changes") {
                DiffView(diff: preview.diff)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var steps: [String] {
        let target = model.abbreviatingHome(fix.targetURL.path)
        let winner = model.abbreviatingHome(fix.winner.source.path)
        var steps: [String]
        switch fix.action {
        case .removeCopy:
            steps = ["Strata moves \(target) into its backups.", "The copy that runs stays where it is: \(winner)."]
        case .replaceWithWinner:
            steps = [
                "Strata copies \(model.abbreviatingHome(fix.sourceURL?.path ?? "")) over \(target).",
                "The old copy goes into Strata's backups first.",
            ]
            if fix.winner.scope == .user, fix.target.scope == .project {
                steps.append("This puts your personal copy in the repository, so everyone who uses the repository gets it.")
            } else if fix.winner.scope == .project, fix.target.scope == .user {
                steps.append("This puts the repository's copy in your personal folder, so every repository you open gets it.")
            }
        }
        steps.append("If either copy changes before you confirm, Strata stops and changes nothing. You can undo the fix afterwards.")
        return steps
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
        case .replaceWithWinner: return "Replace the \(scope) copy of \(name) with the \(winner.scope.title.lowercased()) one?"
        }
    }
}

extension ConfigFix.Action {
    var buttonTitle: String {
        switch self {
        case .removeCopy: "Remove This Copy…"
        case .replaceWithWinner: "Replace With the Copy That Runs…"
        }
    }

    var confirmTitle: String {
        switch self {
        case .removeCopy: "Remove Copy"
        case .replaceWithWinner: "Replace Copy"
        }
    }
}

extension FixRecord {
    var summary: String {
        let verb = action == .removeCopy ? "Removed" : "Replaced"
        return "\(verb) \(itemKind.title.lowercased()) \(itemName) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension FixOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .applied(let record): record.action == .removeCopy ? "Removed" : "Replaced"
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
