import AppKit
import StrataCore
import SwiftUI

/// Settings' About section: the version, and an update check that runs only when clicked.
struct AboutSection: View {
    static let upgradeCommand = "brew upgrade --cask strata-inspector"

    @State private var result: UpdateCheckResult?
    @State private var isChecking = false

    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: "\(version) (\(build))")
                .textSelection(.enabled)
            LabeledContent {
                if isChecking {
                    ProgressView().controlSize(.small)
                }
                Button("Check for Updates") { Task { await check() } }
                    .disabled(isChecking)
                    .accessibilityIdentifier("checkForUpdates")
            } label: {
                Text("Updates")
                Text("Asks GitHub for the latest release, only when you click. Homebrew installs updates; Strata never downloads anything.")
            }
            if let result {
                outcome(result)
            }
        }
    }

    @ViewBuilder private func outcome(_ result: UpdateCheckResult) -> some View {
        switch result {
        case .upToDate(let current):
            Label("Strata \(current) is up to date.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .available(let latest, let releaseNotes):
            VStack(alignment: .leading, spacing: 6) {
                Label("Strata \(latest) is available.", systemImage: "arrow.down.circle")
                Link("Release Notes", destination: releaseNotes)
                LabeledContent {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
                    }
                    .accessibilityLabel("Copy upgrade command")
                } label: {
                    Text(Self.upgradeCommand)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        result = await UpdateChecker.live.check(currentVersion: version)
    }
}

extension UpdateChecker {
    /// One GET with no cookies, cache or stored credentials.
    static let live = UpdateChecker { url in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Strata", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = Dictionary(
            http.allHeaderFields.compactMap { key, value in (key as? String).map { ($0, "\(value)") } },
            uniquingKeysWith: { first, _ in first }
        )
        return HTTPReply(status: http.statusCode, headers: headers, body: data)
    }
}
