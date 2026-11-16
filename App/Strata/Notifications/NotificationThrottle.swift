import Foundation

/// Decides when to announce pending changes. A burst of edits becomes one notification, and a change that has
/// been announced isn't announced again while it's still waiting for review.
struct NotificationThrottle {
    /// How long to wait after the latest new change, so the rest of a burst can land.
    var settle: TimeInterval
    /// The longest a change waits, so a stream of edits can't hold notifications back for ever.
    var maximumWait: TimeInterval

    private(set) var announced: Set<String> = []
    private var waiting: Set<String> = []
    private var firstSeen: Date?
    private var lastSeen: Date?

    /// Spelled out because the private state above makes the synthesized one private.
    init(settle: TimeInterval = 5, maximumWait: TimeInterval = 30) {
        self.settle = settle
        self.maximumWait = maximumWait
    }

    /// When the waiting changes are due, or nil when nothing new is waiting.
    var dueDate: Date? {
        guard let firstSeen, let lastSeen else { return nil }
        return min(lastSeen.addingTimeInterval(settle), firstSeen.addingTimeInterval(maximumWait))
    }

    /// Takes the latest pending change IDs and returns when they're due. A change that's gone, because it was
    /// reviewed or undone, is forgotten, so it's announced again if it comes back.
    mutating func observe(_ ids: [String], at now: Date) -> Date? {
        let current = Set(ids)
        announced.formIntersection(current)
        let fresh = current.subtracting(announced)
        guard !fresh.isEmpty else {
            waiting = []
            firstSeen = nil
            lastSeen = nil
            return nil
        }
        if firstSeen == nil || !fresh.isSubset(of: waiting) {
            firstSeen = firstSeen ?? now
            lastSeen = now
        }
        waiting = fresh
        return dueDate
    }

    /// The changes to announce at `now`, in the order given, or nil when none are due. Announced changes are
    /// remembered until they leave the pending list.
    mutating func due(_ ids: [String], at now: Date) -> [String]? {
        guard let dueDate = observe(ids, at: now), now >= dueDate else { return nil }
        let result = ids.filter(waiting.contains)
        announced.formUnion(waiting)
        waiting = []
        firstSeen = nil
        lastSeen = nil
        return result
    }
}
