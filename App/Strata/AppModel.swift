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
    var query = ItemQuery()
    var selectedItemID: ConfigItem.ID?
    var isInspectorPresented = true

    let environment: ScanEnvironment
    private let store: RepositoryStore
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private var fileWatcher: FileWatcher?
    @ObservationIgnored private lazy var scheduler = RefreshScheduler { [weak self] batch in
        guard let self else { return }
        Task { await self.refresh(batch) }
    }

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

    /// Items for the current category that match the search and filters, in report order.
    var visibleItems: [ConfigItem] {
        guard category != .issues, let report = selectedReport else { return [] }
        return query.apply(to: report.items.filter { category.includes($0.kind) }, in: report)
    }

    /// Diagnostics matching the search text.
    var visibleDiagnostics: [Diagnostic] {
        query.apply(to: selectedReport?.diagnostics ?? [])
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

    // MARK: - Automatic refresh

    /// Starts or stops watching the repositories and global configuration. Call again when the repository list changes.
    func configureWatching(enabled: Bool) {
        folderWatcher?.stop()
        fileWatcher?.stop()
        folderWatcher = nil
        fileWatcher = nil
        scheduler.cancel()
        guard enabled else { return }

        let available = repositories.filter { !missingRepositoryIDs.contains($0.id) }.map(\.url.path)
        let relevance = ChangeRelevance(environment: environment, repositoryPaths: available)
        var paths = available + [environment.claudeDirectory.path]
        if let managed = environment.managedDirectory, FileManager.default.fileExists(atPath: managed.path) {
            paths.append(managed.path)
        }
        let watcher = FolderWatcher(paths: paths) { [weak self] changed in
            let affected = changed.map(relevance.classify)
            Task { @MainActor [weak self] in
                affected.forEach { self?.scheduler.enqueue($0) }
            }
        }
        let globalFile = FileWatcher(url: environment.globalConfigFile) { [weak self] in
            Task { @MainActor [weak self] in self?.scheduler.enqueue(.global) }
        }
        watcher.start()
        globalFile.start()
        folderWatcher = watcher
        fileWatcher = globalFile
    }

    /// Rescans what a batch of changes affects: every scanned repository for global changes, otherwise only those repositories.
    func refresh(_ batch: RefreshScheduler.Batch) async {
        let targets = repositories.filter { repository in
            guard reports[repository.id] != nil else { return false }
            return batch.global || batch.repositoryPaths.contains(repository.url.standardizedFileURL.path)
        }
        for repository in targets {
            await scan(repository.id)
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
