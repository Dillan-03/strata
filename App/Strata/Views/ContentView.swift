import StrataCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PreferenceKey.autoRefresh) private var autoRefresh = true

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 232)
        } detail: {
            if let repository = model.selectedRepository {
                if model.isMissing(repository.id) {
                    MissingRepositoryView(repository: repository)
                } else {
                    RepositoryDetailView(repository: repository)
                }
            } else {
                EmptyRepositoriesView()
            }
        }
        .onChange(of: model.selectedRepositoryID) {
            model.selectedItemID = nil
        }
        .onChange(of: model.repositories) {
            model.configureWatching(enabled: autoRefresh)
        }
        .onChange(of: autoRefresh) {
            model.configureWatching(enabled: autoRefresh)
        }
        .onAppear {
            model.configureWatching(enabled: autoRefresh)
        }
        .sheet(isPresented: $model.isReviewingChanges) {
            ChangeReviewSheet()
                .environment(model)
        }
        .sheet(item: $model.proposedFix) { fix in
            FixReviewSheet(fix: fix, repositoryID: model.selectedRepositoryID)
                .environment(model)
        }
        .sheet(isPresented: $model.isCheckingPluginUpdates) {
            PluginUpdatesSheet()
                .environment(model)
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
                    RepositoryRow(
                        repository: repository,
                        isMissing: model.isMissing(repository.id),
                        issueCount: model.reports[repository.id]?.diagnostics.filter { $0.severity != .info }.count ?? 0
                    )
                    .tag(repository.id)
                    .contextMenu {
                        if model.isMissing(repository.id) {
                            Button("Locate…") { model.presentLocatePanel(for: repository.id) }
                        } else {
                            Button("Reveal in Finder") { model.revealInFinder(repository.url) }
                            Button("Rescan") { Task { await model.scan(repository.id) } }
                            Toggle("Notify About Changes", isOn: Binding(
                                get: { model.notifiesAboutChanges(in: repository.id) },
                                set: { model.setNotifiesAboutChanges($0, in: repository.id) }
                            ))
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
    let issueCount: Int

    var body: some View {
        Label {
            Text(repository.displayName)
                .foregroundStyle(isMissing ? .secondary : .primary)
        } icon: {
            Image(systemName: isMissing ? "questionmark.folder" : "folder")
        }
        .badge(issueCount)
        .help(isMissing ? "Can't find \(repository.url.path)" : repository.url.path)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if isMissing { return "\(repository.displayName), missing" }
        if issueCount > 0 { return "\(repository.displayName), \(issueCount) issue\(issueCount == 1 ? "" : "s")" }
        return repository.displayName
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
