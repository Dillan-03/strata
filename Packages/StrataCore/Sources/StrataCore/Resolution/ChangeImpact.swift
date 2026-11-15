import Foundation

/// How one change plays out in one saved repository.
public struct RepositoryImpact: Hashable, Sendable {
    public enum Effect: Hashable, Sendable {
        /// What Claude Code uses in this repository changes.
        case affected
        /// The item only applies under a condition here, or static inspection can't tell.
        case possiblyAffected
        /// This repository's own definition, or a higher-priority one, wins before and after, so nothing changes here.
        case shadowed(by: ConfigItem)
        /// The item isn't used here: it's inactive, invalid, or doesn't reach this repository.
        case unaffected
    }

    public let repositoryPath: String
    public let effect: Effect

    public var isAffected: Bool { effect == .affected }
}

/// Works out which saved repositories a change reaches, using a scan of each taken before and after the change.
public enum ChangeImpact {
    /// Reports are matched by repository path. A repository missing from either side is skipped, since there's
    /// nothing to compare.
    public static func impacts(of change: ConfigChange, before: [InspectionReport], after: [InspectionReport]) -> [RepositoryImpact] {
        let earlier = Dictionary(before.map { ($0.repositoryPath, $0) }, uniquingKeysWith: { first, _ in first })
        return after.compactMap { now in
            guard let then = earlier[now.repositoryPath] else { return nil }
            let was = find(change.previous ?? change.item, in: then)
            let isNow = change.kind == .deleted ? nil : find(change.item, in: now)
            return RepositoryImpact(repositoryPath: now.repositoryPath, effect: effect(before: was, after: isNow, then: then, now: now))
        }
        .sorted { $0.repositoryPath < $1.repositoryPath }
    }

    /// The same item as seen from another repository's scan. Plugins are matched by ID, because the settings file
    /// that decides a plugin, and so its item identity, can differ per repository.
    static func find(_ item: ConfigItem, in report: InspectionReport) -> ConfigItem? {
        if item.kind == .plugin {
            return report.items.first { $0.kind == .plugin && $0.name == item.name }
        }
        return report.item(withID: item.id)
    }

    private static func effect(before: ConfigItem?, after: ConfigItem?, then: InspectionReport, now: InspectionReport) -> RepositoryImpact.Effect {
        let states = [before?.applicability, after?.applicability].compactMap { $0 }
        if states.contains(where: \.isApplied) { return .affected }
        if states.contains(where: { $0 == .conditional || $0 == .unknown }) { return .possiblyAffected }
        if case .shadowed(let id)? = after?.applicability, let winner = now.item(withID: id) { return .shadowed(by: winner) }
        if case .shadowed(let id)? = before?.applicability, let winner = then.item(withID: id) { return .shadowed(by: winner) }
        return .unaffected
    }
}
