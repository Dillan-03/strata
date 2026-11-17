import StrataCore
import SwiftUI

/// Settings' About section: the version, and an update check that runs when clicked, or at launch if turned on.
struct AboutSection: View {
    static let upgradeCommand = "brew upgrade --cask strata-inspector"

    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.checksForUpdatesAutomatically) private var checksAutomatically = false

    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: "\(AppModel.marketingVersion) (\(build))")
                .textSelection(.enabled)
            LabeledContent {
                if model.isCheckingForUpdates {
                    ProgressView().controlSize(.small)
                }
                Button("Check for Updates") { Task { await model.checkForUpdates() } }
                    .disabled(model.isCheckingForUpdates)
                    .accessibilityIdentifier("checkForUpdates")
            } label: {
                Text("Updates")
                Text("Asks GitHub for the latest release. Homebrew installs updates; Strata never downloads anything.")
            }
            Toggle(isOn: $checksAutomatically) {
                Text("Check for updates automatically")
                Text(
                    "Off by default. When it's on, Strata asks GitHub when it opens, at most once a day, "
                        + "and shows a notice in the sidebar when there's a new version."
                )
            }
            .accessibilityIdentifier("checksForUpdatesAutomatically")
            if let result = model.updateCheckResult {
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
                CommandRow(command: Self.upgradeCommand)
            }
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown at the bottom of the sidebar when an update check found a newer version. Opens Settings, which says how to upgrade.
struct UpdateAvailableNotice: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .available(let latest, _) = model.updateCheckResult {
            SettingsLink {
                Label("Strata \(latest) is available", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .accessibilityIdentifier("updateAvailableNotice")
        }
    }
}

extension AppModel {
    static let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

    func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        updateCheckResult = await UpdateChecker.live.check(currentVersion: Self.marketingVersion)
    }

    /// Checks at launch when the user turned automatic checks on and a day has passed since the last one.
    func checkForUpdatesIfDue(defaults: UserDefaults, now: Date = .now) async {
        // ponytail: launch only, so a window left open for days doesn't recheck until Strata reopens. Add a timer if that matters.
        guard defaults.bool(forKey: PreferenceKey.checksForUpdatesAutomatically) else { return }
        let last = defaults.object(forKey: PreferenceKey.lastAutomaticUpdateCheck) as? Date
        guard UpdateChecker.isAutomaticCheckDue(lastChecked: last, now: now) else { return }
        defaults.set(now, forKey: PreferenceKey.lastAutomaticUpdateCheck)
        await checkForUpdates()
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
