import Foundation

/// Search across every added repository's report. Configuration that lives outside the repositories (personal, managed,
/// plugin and claude.ai items) appears in every report, so it's listed once, with its status in each repository.
public enum CrossRepositorySearch {
    public struct RepositoryHits: Identifiable, Hashable, Sendable {
        public let repositoryID: Repository.ID
        public let items: [ConfigItem]
        public var id: Repository.ID { repositoryID }
    }

    public struct SharedHit: Identifiable, Hashable, Sendable {
        /// The item as the first repository that has it sees it.
        public let item: ConfigItem
        /// Its status in each repository, in the order the repositories were given.
        public let statuses: [Repository.ID: Applicability]
        public var id: ConfigItem.ID { item.id }
    }

    public struct Results: Hashable, Sendable {
        public let shared: [SharedHit]
        public let byRepository: [RepositoryHits]
        public var isEmpty: Bool { shared.isEmpty && byRepository.isEmpty }
        public var count: Int { shared.count + byRepository.map(\.items.count).reduce(0, +) }
    }

    static let sharedScopes: Set<Scope> = [.user, .managed, .plugin, .synced]

    /// `reports` in sidebar order. `kinds` limits the search to a category; nil means every kind.
    public static func results(for query: ItemQuery, in reports: [(Repository.ID, InspectionReport)], kinds: Set<ItemKind>?) -> Results {
        var shared: [ConfigItem.ID: (item: ConfigItem, statuses: [Repository.ID: Applicability])] = [:]
        var sharedOrder: [ConfigItem.ID] = []
        var byRepository: [RepositoryHits] = []
        for (repositoryID, report) in reports {
            let candidates = kinds.map { kinds in report.items.filter { kinds.contains($0.kind) } } ?? report.items
            var own: [ConfigItem] = []
            for item in query.apply(to: candidates, in: report) {
                if sharedScopes.contains(item.scope) {
                    if shared[item.id] == nil {
                        shared[item.id] = (item, [:])
                        sharedOrder.append(item.id)
                    }
                    shared[item.id]?.statuses[repositoryID] = item.applicability
                } else {
                    own.append(item)
                }
            }
            if !own.isEmpty { byRepository.append(RepositoryHits(repositoryID: repositoryID, items: own)) }
        }
        return Results(
            shared: sharedOrder.compactMap { id in shared[id].map { SharedHit(item: $0.item, statuses: $0.statuses) } },
            byRepository: byRepository
        )
    }
}
