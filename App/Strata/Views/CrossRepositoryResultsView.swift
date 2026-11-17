import StrataCore
import SwiftUI

/// Where the search box looks.
enum SearchScope: Hashable {
    case repository
    case all
}

/// Search results from every added repository. Personal, managed and plugin items appear once, with their status in each.
struct CrossRepositoryResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let results = model.crossRepositoryResults
        if results.isEmpty {
            ContentUnavailableView.search(text: model.query.text)
        } else {
            List {
                if !results.shared.isEmpty {
                    Section("Everywhere: personal, managed and plugin (\(results.shared.count))") {
                        ForEach(results.shared) { hit in
                            row(hit.item, detail: statusSummary(hit), repositoryID: model.selectedRepositoryID)
                        }
                    }
                }
                ForEach(results.byRepository) { hits in
                    Section("\(name(of: hits.repositoryID)) (\(hits.items.count))") {
                        ForEach(hits.items) { item in
                            row(item, detail: "\(item.scope.title) · \(item.applicability.title)", repositoryID: hits.repositoryID)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("crossRepositoryResults")
        }
    }

    private func row(_ item: ConfigItem, detail: String, repositoryID: Repository.ID?) -> some View {
        Button {
            if let repositoryID { model.open(item.id, in: repositoryID) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.invocation ?? item.name)
                    .font(item.kind == .instruction ? .body : .body.monospaced())
                Text("\(item.kind.title) · \(detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("searchResult.\(item.kind.rawValue).\(item.scope.rawValue).\(item.name)")
    }

    /// "Applies in api, web · Overridden in docs"
    private func statusSummary(_ hit: CrossRepositorySearch.SharedHit) -> String {
        let grouped = Dictionary(grouping: model.repositories.filter { hit.statuses[$0.id] != nil }) { hit.statuses[$0.id]?.title ?? "" }
        return grouped.keys.sorted().map { status in
            "\(status) in \(grouped[status, default: []].map(\.displayName).joined(separator: ", "))"
        }.joined(separator: " · ")
    }

    private func name(of id: Repository.ID) -> String {
        model.repositories.first { $0.id == id }?.displayName ?? "Repository"
    }
}

extension AppModel {
    var crossRepositoryResults: CrossRepositorySearch.Results {
        let reports = repositories.compactMap { repository in reports[repository.id].map { (repository.id, $0) } }
        return CrossRepositorySearch.results(for: query, in: reports, kinds: category == .issues ? [] : category.kinds)
    }

    /// Switches to the repository and selects the item there, keeping the search text.
    func open(_ itemID: ConfigItem.ID, in repositoryID: Repository.ID) {
        searchScope = .repository
        selectedRepositoryID = repositoryID
        reveal(itemID)
    }

    func scanUnscannedRepositories() async {
        for repository in repositories where reports[repository.id] == nil && !isMissing(repository.id) {
            await scan(repository.id)
        }
    }
}
