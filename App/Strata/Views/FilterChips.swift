import StrataCore
import SwiftUI

/// Chips above the item list for the Filter menu's filters, each with how many items picking it would show.
struct FilterChips: View {
    @Environment(AppModel.self) private var model
    let items: [ConfigItem]
    let report: InspectionReport

    var body: some View {
        @Bindable var model = model
        let counts = model.query.counts(in: items, report: report)
        // A chip that's on stays, even at zero, so it can always be turned off.
        let statuses = ItemQuery.Status.allCases.filter { counts.statuses[$0, default: 0] > 0 || model.query[status: $0] }
        let scopes = Scope.allCases.filter { counts.scopes[$0, default: 0] > 0 || model.query[scope: $0] }
        let showsIssues = counts.withIssues > 0 || model.query.onlyWithIssues
        if !statuses.isEmpty || !scopes.isEmpty || showsIssues {
            FlowLayout(spacing: 6) {
                ForEach(statuses, id: \.self) { status in
                    chip(status.title, count: counts.statuses[status, default: 0], isOn: $model.query[status: status], id: "status.\(status.rawValue)")
                }
                ForEach(scopes, id: \.self) { scope in
                    chip(scope.title, count: counts.scopes[scope, default: 0], isOn: $model.query[scope: scope], id: "scope.\(scope.rawValue)")
                }
                if showsIssues {
                    chip("Has Issues", count: counts.withIssues, isOn: $model.query.onlyWithIssues, id: "issues")
                }
                if model.query.hasFilters {
                    Button("Clear") { model.query.clearFilters() }
                        .buttonBorderShape(.capsule)
                        .help("Turn off every filter")
                        .accessibilityLabel("Clear Filters")
                        .accessibilityIdentifier("filterChip.clear")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func chip(_ title: String, count: Int, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            Text("\(title) \(Text("\(count)").monospacedDigit().foregroundStyle(.secondary))")
        }
        .toggleStyle(.button)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("\(title), \(count) item\(count == 1 ? "" : "s")")
        .accessibilityIdentifier("filterChip.\(id)")
    }
}

/// Lays subviews out left to right, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var top = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var left = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: left, y: top + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                left += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
