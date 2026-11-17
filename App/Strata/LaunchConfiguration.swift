import Foundation

/// How the app was launched. UI tests pass `-StrataUITesting` so they get an empty, throwaway preferences domain
/// and fixture folders instead of the user's own repositories and configuration.
struct LaunchConfiguration {
    static let uiTestingArgument = "-StrataUITesting"
    static let uiTestingSuite = "com.dillankerai.strata.uitests"
    static let repositoryEnvironmentKey = "STRATA_UITEST_REPOSITORY"
    static let homeEnvironmentKey = "STRATA_UITEST_HOME"

    let isUITesting: Bool
    /// True when the app is only hosting unit tests, which must not touch macOS notifications.
    var isHostingUnitTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    let defaults: UserDefaults
    /// UI tests can pass several, separated by `:`.
    let initialRepositories: [URL]
    let homeOverride: URL?

    static func current(processInfo: ProcessInfo = .processInfo) -> LaunchConfiguration {
        let isUITesting = processInfo.arguments.contains(uiTestingArgument)
        guard isUITesting, let suite = UserDefaults(suiteName: uiTestingSuite) else {
            return LaunchConfiguration(isUITesting: false, defaults: .standard, initialRepositories: [], homeOverride: nil)
        }
        suite.removePersistentDomain(forName: uiTestingSuite)
        let environment = processInfo.environment
        return LaunchConfiguration(
            isUITesting: true,
            defaults: suite,
            initialRepositories: (environment[repositoryEnvironmentKey] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) },
            homeOverride: environment[homeEnvironmentKey].map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }
}
