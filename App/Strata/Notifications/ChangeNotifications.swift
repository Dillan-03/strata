import AppKit
import Foundation
import StrataCore
import UserNotifications

/// Receives changes that are due to be announced. The app posts macOS notifications; tests record them.
@MainActor
protocol ChangeAnnouncing: AnyObject {
    func announce(_ changes: [PendingChange])
}

/// Notification settings, kept in the same defaults as the repository list.
struct NotificationPreferences {
    static let enabledKey = "notifyAboutChanges"
    static let pausedUntilKey = "notificationsPausedUntil"
    static let mutedRepositoriesKey = "mutedRepositoryIDs"

    let defaults: UserDefaults

    /// Off until the user turns it on, because turning it on asks macOS for permission.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    var pausedUntil: Date? {
        let interval = defaults.double(forKey: Self.pausedUntilKey)
        return interval > 0 ? Date(timeIntervalSinceReferenceDate: interval) : nil
    }

    func allowsAnnouncements(at now: Date) -> Bool {
        isEnabled && (pausedUntil.map { $0 <= now } ?? true)
    }

    var mutedRepositoryIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: Self.mutedRepositoriesKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func saveMutedRepositoryIDs(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.mutedRepositoriesKey)
    }
}

enum ChangeNotificationText {
    static let title = "Claude Code configuration changed"

    /// One change is named in full; several are named two at a time, with a count for the rest.
    static func body(for changes: [PendingChange]) -> String {
        guard let first = changes.first?.change else { return "" }
        if changes.count == 1 {
            return "\(first.item.kind.title) \(name(first)) was \(verb(first.kind)) (\(first.item.scope.title.lowercased()))."
        }
        let names = changes.prefix(2).map { name($0.change) }
        let rest = changes.count - names.count
        let list = rest > 0 ? "\(names.joined(separator: ", ")) and \(rest) more" : names.joined(separator: " and ")
        return "\(list) changed. Open Strata to review them."
    }

    private static func name(_ change: ConfigChange) -> String {
        change.item.invocation ?? change.item.name
    }

    private static func verb(_ kind: ConfigChange.Kind) -> String {
        switch kind {
        case .created: "added"
        case .updated: "edited"
        case .deleted: "removed"
        case .renamed: "moved"
        }
    }
}

/// Posts change notifications through macOS, and opens Review Changes when one is clicked.
@MainActor
final class SystemNotifications: NSObject, ChangeAnnouncing, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Called when the user clicks a notification.
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks macOS for permission the first time; afterwards returns what the user chose in System Settings.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func announce(_ changes: [PendingChange]) {
        guard !changes.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = ChangeNotificationText.title
        content.body = ChangeNotificationText.body(for: changes)
        content.threadIdentifier = "configuration-changes"
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NSApp.activate()
            self.onOpen?()
            completionHandler()
        }
    }

    /// While Strata is in front, its own banner already shows the change, so the notification is left in the list.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list])
    }
}
