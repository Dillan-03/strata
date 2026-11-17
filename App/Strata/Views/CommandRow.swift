import AppKit
import SwiftUI

/// A command for the user to run in Terminal, with a button that copies it. Strata never runs it.
struct CommandRow: View {
    var note: String?
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let note {
                Text(note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(command)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .accessibilityLabel("Copy command")
            }
        }
    }
}
