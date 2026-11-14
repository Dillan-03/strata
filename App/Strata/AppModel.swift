import AppKit
import Observation
import StrataCore

@MainActor
@Observable
final class AppModel {
    private(set) var repositories: [Repository] = []
    var selectedRepositoryID: Repository.ID?

    var selectedRepository: Repository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    func add(_ url: URL) {
        if let existing = repositories.first(where: { $0.refersToSameFolder(as: url) }) {
            selectedRepositoryID = existing.id
            return
        }
        let repository = Repository(url: url)
        repositories.append(repository)
        selectedRepositoryID = repository.id
    }

    func remove(_ id: Repository.ID) {
        repositories.removeAll { $0.id == id }
        if selectedRepositoryID == id {
            selectedRepositoryID = repositories.first?.id
        }
    }

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
}
