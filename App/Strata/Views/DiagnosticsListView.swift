import StrataCore
import SwiftUI

struct DiagnosticsListView: View {
    @Environment(AppModel.self) private var model
    let report: InspectionReport
    let formatter: PathFormatter

    var body: some View {
        let visible = model.visibleDiagnostics
        if report.diagnostics.isEmpty {
            ContentUnavailableView("No Issues", systemImage: "checkmark.seal", description: Text("Nothing in this repository's configuration needs attention."))
        } else if visible.isEmpty {
            ContentUnavailableView.search(text: model.query.text)
        } else {
            List {
                ForEach(Diagnostic.Severity.allCases, id: \.self) { severity in
                    let diagnostics = visible.filter { $0.severity == severity }
                    if !diagnostics.isEmpty {
                        Section("\(severity.title) (\(diagnostics.count))") {
                            ForEach(diagnostics) { diagnostic in
                                DiagnosticRow(diagnostic: diagnostic, report: report, formatter: formatter)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("diagnosticsList")
        }
    }
}

struct DiagnosticRow: View {
    @Environment(AppModel.self) private var model
    let diagnostic: Diagnostic
    let report: InspectionReport
    let formatter: PathFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SeverityIcon(severity: diagnostic.severity)
            VStack(alignment: .leading, spacing: 4) {
                Text(diagnostic.title)
                    .font(.body.weight(.medium))
                Text(diagnostic.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion = diagnostic.suggestion {
                    Text(suggestion)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // One line when the links fit, one per line when they don't, never wrapped mid-label.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { links }
                    VStack(alignment: .leading, spacing: 4) { links }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    /// Items open in the inspector, which can also reveal their files. Issues about a file with no item,
    /// such as malformed JSON, get Finder links instead.
    @ViewBuilder private var links: some View {
        let items = diagnostic.itemIDs.compactMap { report.item(withID: $0) }
        ForEach(items) { item in
            Button("Show \(item.invocation ?? item.name) (\(item.scope.title))") {
                model.reveal(item.id)
            }
            .buttonStyle(.link)
            .fixedSize()
            .accessibilityIdentifier("showItem.\(item.scope.rawValue).\(item.name)")
        }
        if items.isEmpty {
            ForEach(diagnostic.paths.prefix(2), id: \.self) { path in
                Button("Reveal \(URL(fileURLWithPath: path).lastPathComponent) in Finder") {
                    model.revealInFinder(URL(fileURLWithPath: path))
                }
                .buttonStyle(.link)
                .fixedSize()
                .help(formatter.display(path))
            }
        }
    }
}
