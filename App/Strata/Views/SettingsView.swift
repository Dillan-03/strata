import SwiftUI

enum PreferenceKey {
    static let autoRefresh = "autoRefresh"
}

struct SettingsView: View {
    @AppStorage(PreferenceKey.autoRefresh) private var autoRefresh = true

    var body: some View {
        Form {
            Section {
                Toggle("Refresh automatically when configuration files change", isOn: $autoRefresh)
                Text(
                    "Strata watches your repositories, ~/.claude and ~/.claude.json, and rescans after edits settle. "
                        + "Claude Code's transcripts and logs are ignored. You can always rescan with ⌘R."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Privacy") {
                Text("Strata only reads files. It never changes Claude Code configuration, runs MCP servers, or connects to the network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
