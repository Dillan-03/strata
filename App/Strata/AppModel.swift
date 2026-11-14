import AppKit
import Observation
import StrataCore

@MainActor
@Observable
final class AppModel {
    private(set) var repositories: [Repository] = []
    private(set) var missingRepositoryIDs: Set<Repository.ID> = []
    private(set) var reports: [Repository.ID: InspectionReport] = [:]
    private(set) var scanningRepositoryIDs: Set<Repository.ID> = []

    var selectedRepositoryID: Repository.ID?
    var category: Category = .all
    var selectedItemID: ConfigItem.ID?
    var isInspectorPresented = true

    let environment: ScanEnvironment
    private let store: RepositoryStore

    init(store: RepositoryStore, environment: ScanEnvironment = .current()) {
        self.store = store
        self.environment = environment
        restore()
    }

    // MARK: - Selection

    var selectedRepository: Repository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    var selectedReport: InspectionReport? {
        selectedRepositoryID.flatMap { reports[$0] }
    }

    var selectedItem: ConfigItem? {
        guard let selectedItemID else { return nil }
        return selectedReport?.item(withID: selectedItemID)
    }

    func isMissing(_ id: Repository.ID) -> Bool {
        missingRepositoryIDs.contains(id)
    }

    func isScanning(_ id: Repository.ID) -> Bool {
        scanningRepositoryIDs.contains(id)
    }

    /// Items for the current category, in report order.
    var visibleItems: [ConfigItem] {
        guard category != .issues else { return [] }
        return (selectedReport?.items ?? []).filter { category.includes($0.kind) }
    }

    /// Selects an item, switching category if the current one doesn't show it.
    func reveal(_ itemID: ConfigItem.ID) {
        guard let item = selectedReport?.item(withID: itemID) else { return }
        if !category.includes(item.kind) || category == .issues {
            category = .all
        }
        selectedItemID = itemID
        isInspectorPresented = true
    }

    func pathFormatter(for repository: Repository) -> PathFormatter {
        PathFormatter(repositoryPath: repository.url.standardizedFileURL.path, homePath: environment.homeDirectory.path)
    }

    // MARK: - Scanning

    func scanSelectedRepository() async {
        guard let id = selectedRepositoryID else { return }
        await scan(id)
    }

    func scan(_ id: Repository.ID) async {
        guard let repository = repositories.first(where: { $0.id == id }), !scanningRepositoryIDs.contains(id) else { return }
        scanningRepositoryIDs.insert(id)
        defer { scanningRepositoryIDs.remove(id) }

        let inspector = Inspector(environment: environment)
        let url = repository.url
        let report = await Task.detached(priority: .userInitiated) {
            inspector.inspect(url)
        }.value

        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists {
            missingRepositoryIDs.remove(id)
        } else {
            missingRepositoryIDs.insert(id)
        }
        reports[id] = report
        if let selectedItemID, report.item(withID: selectedItemID) == nil, selectedRepositoryID == id {
            self.selectedItemID = nil
        }
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
        reports[id] = nil
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
        reports[id] = nil
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

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
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
