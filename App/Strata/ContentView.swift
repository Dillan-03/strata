import StrataCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 232)
        } detail: {
            if let repository = model.selectedRepository {
                if model.isMissing(repository.id) {
                    MissingRepositoryView(repository: repository)
                } else {
                    RepositoryHeader(repository: repository)
                }
            } else {
                EmptyRepositoriesView()
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedRepositoryID) {
            Section("Repositories") {
                ForEach(model.repositories) { repository in
                    RepositoryRow(repository: repository, isMissing: model.isMissing(repository.id))
                        .tag(repository.id)
                        .contextMenu {
                            if model.isMissing(repository.id) {
                                Button("Locate…") { model.presentLocatePanel(for: repository.id) }
                            } else {
                                Button("Reveal in Finder") { model.revealInFinder(repository.url) }
                            }
                            Divider()
                            Button("Remove from Strata") { model.remove(repository.id) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.presentAddRepositoryPanel()
            } label: {
                Label("Add Folder…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

private struct RepositoryRow: View {
    let repository: Repository
    let isMissing: Bool

    var body: some View {
        Label {
            Text(repository.displayName)
                .foregroundStyle(isMissing ? .secondary : .primary)
        } icon: {
            Image(systemName: isMissing ? "questionmark.folder" : "folder")
        }
        .help(isMissing ? "Can't find \(repository.url.path)" : repository.url.path)
        .accessibilityLabel(isMissing ? "\(repository.displayName), missing" : repository.displayName)
    }
}

private struct RepositoryHeader: View {
    let repository: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repository.displayName)
                .font(.title2.weight(.semibold))
            Text(repository.url.path)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .navigationTitle(repository.displayName)
        .navigationSubtitle(repository.url.path)
    }
}

private struct MissingRepositoryView: View {
    @Environment(AppModel.self) private var model
    let repository: Repository

    var body: some View {
        ContentUnavailableView {
            Label("Can't Find \(repository.displayName)", systemImage: "questionmark.folder")
        } description: {
            Text("Nothing is at \(repository.url.path). The folder may have been moved, renamed or deleted, or its disk isn't connected.")
        } actions: {
            Button("Locate…") { model.presentLocatePanel(for: repository.id) }
                .buttonStyle(.borderedProminent)
            Button("Remove from Strata") { model.remove(repository.id) }
        }
        .navigationTitle(repository.displayName)
    }
}

private struct EmptyRepositoriesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Repositories", systemImage: "folder.badge.plus")
        } description: {
            Text(
                "Add a repository to see which Claude Code skills, agents, MCP servers, plugins "
                    + "and instructions apply to it, and where each one comes from."
            )
        } actions: {
            Button("Add Repository…") {
                model.presentAddRepositoryPanel()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("addRepositoryButton")
        }
    }
}
