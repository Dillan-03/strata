import StrataCore
import SwiftUI

/// The status of an item, as an icon plus words so it never relies on colour alone.
struct StatusBadge: View {
    let applicability: Applicability
    /// `.increased` on a selected row, where accent colours lose contrast against the selection.
    @Environment(\.backgroundProminence) private var backgroundProminence

    var body: some View {
        Label(applicability.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(backgroundProminence == .increased ? AnyShapeStyle(.primary) : style)
            .font(.callout)
            .lineLimit(1)
    }

    private var symbol: String {
        switch applicability {
        case .effective: "checkmark.circle.fill"
        case .combined: "square.stack.3d.up.fill"
        case .shadowed: "eye.slash"
        case .conditional: "clock"
        case .inactive: "minus.circle"
        case .invalid: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private var style: AnyShapeStyle {
        switch applicability {
        case .effective, .combined: AnyShapeStyle(.green)
        case .shadowed, .invalid: AnyShapeStyle(.orange)
        case .conditional: AnyShapeStyle(.blue)
        case .inactive, .unknown: AnyShapeStyle(.secondary)
        }
    }
}

struct SeverityIcon: View {
    let severity: Diagnostic.Severity

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityLabel(severity.title)
    }

    private var symbol: String {
        switch severity {
        case .conflict: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    private var color: Color {
        switch severity {
        case .conflict: .red
        case .warning: .orange
        case .info: .secondary
        }
    }
}
