import Foundation

/// Where an item stands since the last review, as far as the files show.
///
/// Strata can't see inside a running Claude Code session, so no status claims a session is up to date. The
/// closest is `unchanged`: nothing about the item changed on disk since the last review. Statuses that need Strata
/// to write configuration ("update available", "update failed") belong with approved updates, which don't exist yet.
public enum SyncStatus: Hashable, Sendable {
    /// Nothing about the item changed on disk since the last review.
    case unchanged
    /// Changed, and the Claude Code docs say a running session picks it up by itself, at once or when it's next used.
    case changeDetected
    /// Changed, and a running session needs a reload command or a new session before it sees the change.
    case actionRequired(SessionPickup.Timing)
    /// Changed, and Strata reports a conflict or warning for it now, so it may not apply the way the file reads.
    case conflict
    /// Changed, and the docs don't say when a running session picks it up.
    case unableToVerify

    /// The status for an item, given its pending change if it has one and the problems Strata reports for it now.
    public static func of(_ change: ConfigChange?, conflicts: [Diagnostic]) -> SyncStatus {
        guard let change else { return .unchanged }
        if conflicts.contains(where: { $0.severity != .info }) { return .conflict }
        switch change.pickup.timing {
        case .live, .onDemand: return .changeDetected
        case .reloadSkills, .reloadPlugins, .nextSession: return .actionRequired(change.pickup.timing)
        case .unknown: return .unableToVerify
        }
    }
}
