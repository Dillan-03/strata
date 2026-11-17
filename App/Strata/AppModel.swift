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
    /// Changes since the last review, across every scanned repository.
    private(set) var pendingChanges: [PendingChange] = []
    var isReviewingChanges = false
    /// The change Review Changes opens on, when it's opened from one item.
    var reviewSelection: PendingChange.ID?
    /// A fix waiting for approval on the fix review screen.
    var proposedFix: ConfigFix?
    /// The last fix that failed for each item, shown in its inspector until a fix succeeds.
    private(set) var failedFixes: [ConfigItem.ID: String] = [:]
    /// Fixes Strata made, newest first, read from their backups.
    private(set) var fixRecords: [FixRecord] = []
    /// Pending changes by item, for list rows. Observed, so rows update when a change arrives or is reviewed.
    private var pendingChangesByItem: [ConfigItem.ID: [PendingChange]] = [:]
    /// Repositories whose changes never trigger a notification. They still show in Review Changes.
    private(set) var mutedRepositoryIDs: Set<Repository.ID> = []
    /// Posts notifications for changes once they're due. Nil when the app runs under tests.
    @ObservationIgnored var announcer: ChangeAnnouncing?
    @ObservationIgnored var throttle = NotificationThrottle()
    @ObservationIgnored private var announcementTask: Task<Void, Never>?

    var selectedRepositoryID: Repository.ID?
    var category: Category = .all
    var query = ItemQuery()
    var selectedItemID: ConfigItem.ID?
    var isInspectorPresented = true

    let environment: ScanEnvironment
    private let store: RepositoryStore
    /// Each repository's report as of the last review: its first scan this launch, or when changes were last marked reviewed.
    private var baselines: [Repository.ID: InspectionReport] = [:]
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private var fileWatcher: FileWatcher?
    @ObservationIgnored private lazy var scheduler = RefreshScheduler { [weak self] batch in
        guard let self else { return }
        Task { await self.refresh(batch) }
    }

    init(store: RepositoryStore, environment: ScanEnvironment = .current()) {
        self.store = store
        self.environment = environment
        mutedRepositoryIDs = notificationPreferences.mutedRepositoryIDs
        restore()
        reloadFixRecords()
    }

    var notificationPreferences: NotificationPreferences {
        NotificationPreferences(defaults: store.defaults)
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

    /// Items for the current category, before search and filters, in report order.
    var categoryItems: [ConfigItem] {
        guard category != .issues, let report = selectedReport else { return [] }
        return report.items.filter { category.includes($0.kind) }
    }

    /// Items for the current category that match the search and filters, in report order.
    var visibleItems: [ConfigItem] {
        guard let report = selectedReport else { return [] }
        return query.apply(to: categoryItems, in: report)
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

    /// `~/…` for paths in the home folder; used where a path isn't relative to one repository.
    func abbreviatingHome(_ path: String) -> String {
        PathFormatter(repositoryPath: "", homePath: environment.homeDirectory.path).abbreviatingHome(path)
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
        if !exists {
            baselines[id] = nil
        } else if baselines[id] == nil {
            baselines[id] = report
        }
        updatePendingChanges()
        if let selectedItemID, report.item(withID: selectedItemID) == nil, selectedRepositoryID == id {
            self.selectedItemID = nil
        }
    }

    // MARK: - Changes

    /// When the oldest baseline was taken: changes are listed from this moment.
    var changesSince: Date? {
        baselines.values.map(\.scannedAt).min()
    }

    /// Changes that reach a repository: its own, plus global and parent-folder ones.
    func changes(reaching id: Repository.ID) -> [PendingChange] {
        pendingChanges.filter { $0.repositoryIDs.contains(id) }
    }

    /// An item's pending change in one repository, if it has one.
    func pendingChange(for itemID: ConfigItem.ID, in repositoryID: Repository.ID) -> PendingChange? {
        pendingChangesByItem[itemID]?.first { $0.repositoryIDs.contains(repositoryID) }
    }

    func syncStatus(of itemID: ConfigItem.ID, in repositoryID: Repository.ID) -> SyncStatus {
        let pending = pendingChange(for: itemID, in: repositoryID)
        return SyncStatus.of(pending?.change, conflicts: pending.map(conflicts(for:)) ?? [])
    }

    /// Opens Review Changes on one change.
    func review(_ pending: PendingChange) {
        reviewSelection = pending.id
        isReviewingChanges = true
    }

    /// Takes the current scans as the new starting point, so the list empties until something changes again.
    func markChangesReviewed() {
        baselines = reports.filter { !missingRepositoryIDs.contains($0.key) }
        pendingChanges = []
        pendingChangesByItem = [:]
        scheduleAnnouncement()
    }

    // MARK: - Fixes

    /// Backups sit under the home Strata inspects, so UI tests keep theirs inside the fixture.
    var fixBackupDirectory: URL {
        environment.homeDirectory.appendingPathComponent("Library/Application Support/Strata/Backups", isDirectory: true)
    }

    var allowsFixes: Bool { store.defaults.bool(forKey: PreferenceKey.allowsFixes) }

    func fixOffer(for item: ConfigItem) -> FixOffer {
        guard let report = selectedReport else { return .none }
        return FixPlanner.offer(for: item, in: report, environment: environment)
    }

    /// Runs a fix the user approved in the repository it was offered for, then rescans so the lists show the result.
    func apply(_ fix: ConfigFix, in repositoryID: Repository.ID) async -> FixOutcome {
        guard allowsFixes else { return .failed("Fixes are turned off in Settings, so Strata changed nothing.") }
        guard let report = reports[repositoryID] else { return .failed("Strata has no scan of this repository.") }
        let writer = ConfigWriter(
            backupDirectory: fixBackupDirectory,
            allowedRoots: FixPlanner.allowedRoots(repositoryPath: report.repositoryPath, environment: environment)
        )
        let outcome: FixOutcome
        do {
            outcome = .applied(try writer.apply(fix))
            failedFixes[fix.target.id] = nil
        } catch {
            failedFixes[fix.target.id] = error.localizedDescription
            outcome = .failed(error.localizedDescription)
        }
        await finishWrite()
        return outcome
    }

    /// Puts back what a fix changed, unless something has changed there since.
    func undo(_ record: FixRecord) async -> FixOutcome {
        let roots = [environment.claudeDirectory] + repositories.map { $0.url.appendingPathComponent(".claude") }
        let outcome: FixOutcome
        do {
            outcome = .undone(try ConfigWriter(backupDirectory: fixBackupDirectory, allowedRoots: roots).undo(record))
        } catch {
            outcome = .failed(error.localizedDescription)
        }
        await finishWrite()
        return outcome
    }

    func reloadFixRecords() {
        fixRecords = ConfigWriter(backupDirectory: fixBackupDirectory, allowedRoots: []).records()
    }

    /// A fix can change ~/.claude, which every repository sees, so every scanned repository is rescanned.
    private func finishWrite() async {
        reloadFixRecords()
        for id in Array(reports.keys) {
            await scan(id)
        }
    }

    // MARK: - Notifications

    func notifiesAboutChanges(in id: Repository.ID) -> Bool {
        !mutedRepositoryIDs.contains(id)
    }

    func setNotifiesAboutChanges(_ notifies: Bool, in id: Repository.ID) {
        if notifies { mutedRepositoryIDs.remove(id) } else { mutedRepositoryIDs.insert(id) }
        notificationPreferences.saveMutedRepositoryIDs(mutedRepositoryIDs)
        scheduleAnnouncement()
    }

    /// Pending changes that reach at least one repository that isn't muted.
    private var announceableChanges: [PendingChange] {
        pendingChanges.filter { !Set($0.repositoryIDs).isSubset(of: mutedRepositoryIDs) }
    }

    /// Restarts the wait for the next announcement. Every change in the pending list goes through here, so a burst
    /// of edits pushes the announcement back until it settles.
    private func scheduleAnnouncement() {
        announcementTask?.cancel()
        guard announcer != nil, let due = throttle.observe(announceableChanges.map(\.id), at: .now) else { return }
        announcementTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.announceDueChanges()
        }
    }

    /// Announces the changes that are due. Changes that come due while notifications are off or paused are
    /// dropped rather than saved up, so turning them back on doesn't bring a flood.
    func announceDueChanges(at now: Date = .now) {
        let candidates = announceableChanges
        guard let due = throttle.due(candidates.map(\.id), at: now) else { return }
        guard notificationPreferences.allowsAnnouncements(at: now) else { return }
        announcer?.announce(candidates.filter { due.contains($0.id) })
    }

    /// What a change does in each repository that had a scan before it: applies, overridden, or out of reach.
    func impacts(of change: ConfigChange) -> [RepositoryEffect] {
        let scanned = repositories.filter { baselines[$0.id] != nil && reports[$0.id] != nil }
        let impacts = ChangeImpact.impacts(
            of: change,
            before: scanned.compactMap { baselines[$0.id] },
            after: scanned.compactMap { reports[$0.id] }
        )
        return impacts.compactMap { impact in
            scanned.first { $0.url.standardizedFileURL.path == impact.repositoryPath }.map { RepositoryEffect(repository: $0, impact: impact) }
        }
    }

    /// A message for the running Claude Code session, describing the change. Strata never sends it.
    func updatePrompt(for pending: PendingChange) -> String {
        UpdatePrompt.make(
            for: pending.change,
            impacts: impacts(of: pending.change).map(\.impact),
            conflicts: conflicts(for: pending),
            homePath: environment.homeDirectory.path
        )
    }

    /// Problems Strata reports for the changed item now, in any repository it reaches.
    func conflicts(for pending: PendingChange) -> [Diagnostic] {
        guard pending.change.kind != .deleted else { return [] }
        var seen = Set<Diagnostic.ID>()
        return pending.repositoryIDs
            .flatMap { reports[$0]?.diagnostics(for: pending.change.item.id) ?? [] }
            .filter { $0.severity != .info && seen.insert($0.id).inserted }
    }

    /// A global change appears in every repository's scan with the same id, so it's listed once with each repository it reached.
    private func updatePendingChanges() {
        var merged: [String: PendingChange] = [:]
        var order: [String] = []
        for repository in repositories {
            guard let baseline = baselines[repository.id], let report = reports[repository.id] else { continue }
            for change in ChangeDetector.changes(from: baseline, to: report) {
                if let existing = merged[change.id] {
                    merged[change.id] = PendingChange(change: existing.change, repositoryIDs: existing.repositoryIDs + [repository.id])
                } else {
                    merged[change.id] = PendingChange(change: change, repositoryIDs: [repository.id])
                    order.append(change.id)
                }
            }
        }
        pendingChanges = order.compactMap { merged[$0] }
        pendingChangesByItem = Dictionary(grouping: pendingChanges, by: \.change.item.id)
        scheduleAnnouncement()
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
        baselines[id] = nil
        if mutedRepositoryIDs.remove(id) != nil {
            notificationPreferences.saveMutedRepositoryIDs(mutedRepositoryIDs)
        }
        updatePendingChanges()
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
        baselines[id] = nil
        updatePendingChanges()
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

/// A change waiting for review, with every repository whose scan showed it.
struct PendingChange: Identifiable, Hashable {
    let change: ConfigChange
    let repositoryIDs: [Repository.ID]

    var id: String { change.id }
}

/// What a change does in one repository.
struct RepositoryEffect: Identifiable {
    let repository: Repository
    let impact: RepositoryImpact

    var id: Repository.ID { repository.id }
}

/// What a fix or an undo did.
enum FixOutcome: Identifiable {
    case applied(FixRecord)
    case undone(FixRecord)
    case failed(String)

    var id: String {
        switch self {
        case .applied(let record): "applied-\(record.id)"
        case .undone(let record): "undone-\(record.id)"
        case .failed(let message): "failed-\(message)"
        }
    }
}
