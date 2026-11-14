import AppKit
import Observation
import StrataCore

@MainActor
@Observable
final class AppModel {
    private(set) var repositories: [Repository] = []
    private(set) var missingRepositoryIDs: Set<Repository.ID> = []
    var selectedRepositoryID: Repository.ID?

    private let store: RepositoryStore

    init(store: RepositoryStore) {
        self.store = store
        restore()
    }

    var selectedRepository: Repository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    func isMissing(_ id: Repository.ID) -> Bool {
        missingRepositoryIDs.contains(id)
    }

    // MARK: - Adding and removing

    func add(_ url: URL) {
        if let existing = repositories.first(where: { $0.refersToSameFolder(as: url) }) {
            selectedRepositoryID = existing.id
            return
        }
        let repository = Repository(url: url)
        repositories.append(repository)
        missingRepositoryIDs.remove(repository.id)
        selectedRepositoryID = repository.id
        persist()
    }

    func remove(_ id: Repository.ID) {
        repositories.removeAll { $0.id == id }
        missingRepositoryIDs.remove(id)
        if selectedRepositoryID == id {
            selectedRepositoryID = repositories.first?.id
        }
        persist()
    }

    /// Points a missing repository at its new location, keeping its place in the list.
    func relocate(_ id: Repository.ID, to url: URL) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].relocate(to: url)
        missingRepositoryIDs.remove(id)
        persist()
    }

    // MARK: - Panels and Finder

    func presentAddRepositoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more repositories to inspect."
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }

    func presentLocatePanel(for id: Repository.ID) {
        guard let repository = repositories.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Locate"
        panel.message = "Where is \(repository.displayName) now?"
        panel.directoryURL = repository.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocate(id, to: url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Persistence

    private func restore() {
        var changed = false
        for entry in store.load() {
            switch RepositoryStore.locate(entry) {
            case .available(let url):
                repositories.append(Repository(id: entry.id, url: url))
            case .moved(let url):
                repositories.append(Repository(id: entry.id, url: url))
                changed = true
            case .missing:
                repositories.append(Repository(id: entry.id, url: URL(fileURLWithPath: entry.path, isDirectory: true)))
                missingRepositoryIDs.insert(entry.id)
            }
        }
        selectedRepositoryID = repositories.first { !missingRepositoryIDs.contains($0.id) }?.id ?? repositories.first?.id
        if changed { persist() }
    }

    private func persist() {
        store.save(repositories.map(RepositoryStore.entry(for:)))
    }
}
