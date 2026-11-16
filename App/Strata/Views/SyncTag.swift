import StrataCore
import SwiftUI

/// A small tag on a list row for an item that changed since the last review.
struct SyncTag: View {
    let status: SyncStatus
    /// `.increased` on the selected row, where the tag's colour loses contrast against the selection.
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        Text(status.shortTitle)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(status.tint))
            .overlay(Capsule().strokeBorder(backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(status.tint.opacity(0.6))))
            .help(status.title)
    }
}

extension SyncStatus {
    var title: String {
        switch self {
        case .unchanged: "No changes since your last review"
        case .changeDetected: "Changed since your last review"
        case .actionRequired(.reloadSkills): "Changed: run /reload-skills to see it"
        case .actionRequired(.reloadPlugins): "Changed: run /reload-plugins to see it"
        case .actionRequired: "Changed: needs a new Claude Code session"
        case .conflict: "Changed, and it has a conflict"
        case .unableToVerify: "Changed: Strata can't tell when it applies"
        }
    }

    var shortTitle: String {
        switch self {
        case .unchanged: "Unchanged"
        case .changeDetected: "Changed"
        case .actionRequired(.reloadSkills), .actionRequired(.reloadPlugins): "Reload needed"
        case .actionRequired: "New session"
        case .conflict: "Conflict"
        case .unableToVerify: "Unverified"
        }
    }

    var symbol: String {
        switch self {
        case .unchanged: "checkmark.circle"
        case .changeDetected: "pencil.circle"
        case .actionRequired: "arrow.clockwise.circle"
        case .conflict: "exclamationmark.triangle"
        case .unableToVerify: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .unchanged: .secondary
        case .changeDetected: .blue
        case .actionRequired: .orange
        case .conflict: .red
        case .unableToVerify: .secondary
        }
    }
}
