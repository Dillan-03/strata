import Foundation

/// One difference between two scans of the same repository: something added, edited, removed or moved on disk,
/// by any editor, tool or `git checkout`.
public struct ConfigChange: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case created, updated, deleted, renamed
    }

    /// Which repositories a change can affect.
    public enum Reach: String, Hashable, Sendable {
        /// Every repository: managed, global, plugin and claude.ai configuration.
        case global
        /// Every repository under a parent folder, through that folder's instruction files.
        case shared
        /// This repository only.
        case repository

        public init(_ scope: Scope) {
            switch scope {
            case .managed, .user, .plugin, .synced: self = .global
            case .ancestor: self = .shared
            case .project, .local, .nested: self = .repository
            }
        }
    }

    public let kind: Kind
    /// The item as it is now, or as it was for a removal.
    public let item: ConfigItem
    /// The item before an edit or a move.
    public let previous: ConfigItem?
    /// What defined the item before, masked. Nil for a creation, or when the scan couldn't read it.
    public let before: ItemContent?
    /// What defines it now, masked. Nil for a removal.
    public let after: ItemContent?
    public let reach: Reach
    public let pickup: SessionPickup

    public var id: String { "\(kind.rawValue):\(previous?.id ?? "-")>\(item.id)" }

    public init(
        kind: Kind,
        item: ConfigItem,
        previous: ConfigItem? = nil,
        before: ItemContent? = nil,
        after: ItemContent? = nil,
        pickup: SessionPickup
    ) {
        self.kind = kind
        self.item = item
        self.previous = previous
        self.before = before
        self.after = after
        self.reach = Reach(item.scope)
        self.pickup = pickup
    }
}

/// Whether a Claude Code session that's already running sees a change, as the Claude Code docs describe it.
/// Strata can't see inside a session, so this is what the docs promise, not an observation.
public struct SessionPickup: Hashable, Sendable {
    public enum Timing: String, Hashable, Sendable {
        /// Picked up within seconds, with nothing to do.
        case live
        /// Loads the next time Claude works in that folder or touches a matching file.
        case onDemand
        /// Run `/reload-skills`.
        case reloadSkills
        /// Run `/reload-plugins`.
        case reloadPlugins
        /// Only a new session sees it.
        case nextSession
        /// The docs don't say.
        case unknown
    }

    public let timing: Timing
    public let explanation: String
    /// The Claude Code docs page the rule comes from.
    public let source: URL?

    public init(_ timing: Timing, _ explanation: String, source: String?) {
        self.timing = timing
        self.explanation = explanation
        self.source = source.flatMap(URL.init(string:))
    }
}
