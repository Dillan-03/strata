import StrataCore
import SwiftUI

/// A change's content: lines for Markdown files, keys for JSON entries. Both sides arrive already masked.
struct DiffView: View {
    let diff: ConfigDiff

    var body: some View {
        switch diff {
        case .text(let text):
            TextDiffView(diff: text)
        case .keyed(let keys):
            KeyDiffView(changes: keys)
        case .unavailable:
            Text("Strata didn't keep this item's content, so it can't show what changed.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TextDiffView: View {
    let diff: TextDiff

    var body: some View {
        if diff.hunks.isEmpty {
            Text("The file's content didn't change.")
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                    if hunk.skippedBefore > 0 {
                        SkippedLines(count: hunk.skippedBefore)
                    }
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineRow(line: line)
                    }
                }
                if diff.skippedAfter > 0 {
                    SkippedLines(count: diff.skippedAfter)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .accessibilityIdentifier("textDiff")
        }
    }
}

private struct DiffLineRow: View {
    let line: TextDiff.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(sign)
                .frame(width: 18)
                .foregroundStyle(tint)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: 40, alignment: .trailing)
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .unchanged: ""
        }
    }

    private var tint: Color {
        switch line.kind {
        case .added: .green
        case .removed: .red
        case .unchanged: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: .green.opacity(0.14)
        case .removed: .red.opacity(0.12)
        case .unchanged: .clear
        }
    }

    private var accessibilityText: String {
        switch line.kind {
        case .added: "Added, line \(line.newNumber ?? 0): \(line.text)"
        case .removed: "Removed, line \(line.oldNumber ?? 0): \(line.text)"
        case .unchanged: "Line \(line.newNumber ?? 0): \(line.text)"
        }
    }
}

private struct SkippedLines: View {
    let count: Int

    var body: some View {
        Text("⋯ \(count) unchanged line\(count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .padding(.leading, 98)
            .background(.quaternary.opacity(0.5))
    }
}

private struct KeyDiffView: View {
    let changes: [KeyChange]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(changes) { change in
                KeyChangeRow(change: change)
            }
        }
        .accessibilityIdentifier("keyDiff")
    }
}

private struct KeyChangeRow: View {
    let change: KeyChange

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(change.path.isEmpty ? "Value" : change.path)
                    .font(.callout.monospaced().weight(change.kind == .unchanged ? .regular : .semibold))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Text(word)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch change.kind {
            case .unchanged:
                value(nil, change.after)
            case .added:
                value("Now", change.after)
            case .removed:
                value("Before", change.before)
            case .changed:
                value("Before", change.before)
                value("Now", change.after)
                if change.changedBehindMask {
                    Text("The value changed, but it's masked, so both look the same.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }
        }
        .foregroundStyle(change.kind == .unchanged ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }

    private func value(_ label: String?, _ text: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            Text(text ?? "—")
                .font(.callout.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.leading, 24)
    }

    private var symbol: String {
        switch change.kind {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .changed: "pencil.circle.fill"
        case .unchanged: "circle"
        }
    }

    private var tint: Color {
        switch change.kind {
        case .added: .green
        case .removed: .red
        case .changed: .blue
        case .unchanged: .secondary
        }
    }

    private var word: String {
        switch change.kind {
        case .added: "Added"
        case .removed: "Removed"
        case .changed: "Changed"
        case .unchanged: "Unchanged"
        }
    }
}
