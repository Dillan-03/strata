import StrataCore
import SwiftUI

/// The breakdown behind the summary bar's token estimate: what loads at launch, the biggest pieces, and what isn't counted.
struct ContextEstimateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let estimate: ContextEstimate

    static func format(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1000) : "\(tokens)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Before your first message", value: "≈\(Self.format(estimate.totalTokens)) tokens")
                        .font(.headline)
                        .accessibilityIdentifier("contextEstimateTotal")
                    LabeledContent("Instruction files", value: "≈\(Self.format(estimate.tokens(for: [.instruction])))")
                    LabeledContent("Skill listing", value: "≈\(Self.format(estimate.tokens(for: [.skill, .command])))")
                    LabeledContent("Subagent descriptions", value: "≈\(Self.format(estimate.tokens(for: [.agent])))")
                    Text("An estimate: characters ÷ \(ContextEstimate.charactersPerToken), because Claude Code doesn't document its tokenizer. Run /context in a session for its own count.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !estimate.warnings.isEmpty {
                    Section("Worth a Look") {
                        ForEach(estimate.warnings, id: \.text) { warning in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(warning.text, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let source = warning.source {
                                    Link("Claude Code docs", destination: source).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("Largest") {
                    ForEach(estimate.entries.prefix(10)) { entry in
                        Button {
                            model.reveal(entry.itemID)
                            dismiss()
                        } label: {
                            LabeledContent {
                                Text("≈\(Self.format(entry.tokens))").monospacedDigit()
                            } label: {
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                Text(entry.kind.title)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Not Counted") {
                    ForEach(ContextEstimate.notCounted, id: \.self) { line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 440, idealHeight: 580)
    }
}
