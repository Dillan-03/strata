import StrataCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedRepositoryID) {
                Section("Repositories") {
                    ForEach(model.repositories) { repository in
                        Label(repository.displayName, systemImage: "folder")
                            .tag(repository.id)
                            .contextMenu {
                                Button("Remove from Strata") { model.remove(repository.id) }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 232)
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
        } detail: {
            if let repository = model.selectedRepository {
                RepositoryHeader(repository: repository)
            } else {
                EmptyRepositoriesView()
            }
        }
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
