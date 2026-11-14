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
                HStack(spacing: 8) {
                    ForEach(diagnostic.itemIDs, id: \.self) { itemID in
                        if let item = report.item(withID: itemID) {
                            Button("Show \(item.invocation ?? item.name) (\(item.scope.title))") {
                                model.reveal(itemID)
                            }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("showItem.\(item.scope.rawValue).\(item.name)")
                        }
                    }
                    ForEach(diagnostic.paths.prefix(2), id: \.self) { path in
                        Button("Reveal \(formatter.display(path))") {
                            model.revealInFinder(URL(fileURLWithPath: path))
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }
}
