import StrataCore
import SwiftUI

/// Shows the exact `claude plugin uninstall` command and what it deletes, then runs it once the user confirms.
struct PluginUninstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var uninstall: PluginUninstall
    let repository: Repository
    @State private var isRunning = false
    @State private var result: AppModel.PluginUninstallResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall the plugin \(uninstall.pluginID)?")
                .font(.title3.bold())
            Text("Strata will run this command in \(model.abbreviatingHome(repository.url.path)):")
                .fixedSize(horizontal: false, vertical: true)
            Text(uninstall.command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Toggle(isOn: $uninstall.keepsData) {
                Text("Keep the plugin's data folder")
                Text("~/.claude/plugins/data/ keeps what the plugin saved, so reinstalling picks up where it left off.")
            }
            .disabled(isRunning || result != nil)
            Text(
                "If this is the last scope the plugin is installed at, Claude Code also deletes its options and secrets. "
                    + "Strata can't undo an uninstall. To get the plugin back, run:"
            )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CommandRow(command: uninstall.reinstallCommand)
            outcome
            HStack {
                if isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if result == nil {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Uninstall", role: .destructive) { Task { await run() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isRunning)
                        .accessibilityIdentifier("confirmPluginUninstall")
                } else {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("pluginUninstallDone")
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(isRunning)
    }

    @ViewBuilder private var outcome: some View {
        switch result {
        case .uninstalled(let output):
            Label(output.isEmpty ? "Uninstalled." : output, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pluginUninstallResult")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pluginUninstallResult")
                CommandRow(note: "You can run it in Terminal instead:", command: uninstall.command)
            }
        case nil:
            EmptyView()
        }
    }

    private func run() async {
        isRunning = true
        result = await model.run(uninstall, in: repository)
        isRunning = false
    }
}

extension AppModel {
    enum PluginUninstallResult: Equatable {
        case uninstalled(String)
        case failed(String)
    }

    /// Runs the command in the repository's folder, which is the project `--scope project` and `--scope local` write to,
    /// then rescans so the list shows what's left.
    func run(_ uninstall: PluginUninstall, in repository: Repository) async -> PluginUninstallResult {
        let candidates = PluginUninstall.executableCandidates(home: environment.homeDirectory)
        guard let claude = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            let places = candidates.map { abbreviatingHome($0.deletingLastPathComponent().path) }.joined(separator: ", ")
            return .failed("Strata couldn't find claude in \(places).")
        }
        let result = await Self.runProcess(claude, arguments: uninstall.arguments, in: repository.url)
        await scan(repository.id)
        return result
    }

    nonisolated private static func runProcess(_ executable: URL, arguments: [String], in directory: URL) async -> PluginUninstallResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = directory
                var environment = ProcessInfo.processInfo.environment
                // Apps get a minimal PATH, and an npm install of claude is a Node script that needs node on it.
                environment["PATH"] = [
                    executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                    environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
                ].joined(separator: ":")
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failed("Couldn't start claude: \(error.localizedDescription)"))
                    return
                }
                // The docs list no prompt for a plain uninstall. If one ever appears, stdin is empty and this stops the wait.
                DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                    if process.isRunning { process.terminate() }
                }
                let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                let text = SecretRedactor.redactText(output.trimmingCharacters(in: .whitespacesAndNewlines))
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .uninstalled(text))
                } else {
                    continuation.resume(returning: .failed(text.isEmpty ? "claude exited with status \(process.terminationStatus)." : text))
                }
            }
        }
    }
}
