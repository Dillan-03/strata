import AppKit
import StrataCore
import SwiftUI
import UniformTypeIdentifiers

/// Saves the selected repository's report as Markdown or JSON, to a file the user picks. Nothing is sent anywhere.
struct ExportReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var format: ReportExport.Format = .markdown
    @State private var onlyVisible = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(ReportExport.Format.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Only what the list shows now (\(model.visibleItems.count) items)", isOn: $onlyVisible)
                        .disabled(model.visibleItems.isEmpty)
                        .help("The current category, search and filters")
                    Text("Secrets are masked and home folder paths become ~. Strata writes only the file you choose.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let failure {
                        Label(failure, systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedReport == nil)
                    .accessibilityIdentifier("saveReportButton")
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func save() {
        guard let report = model.selectedReport else { return }
        let export = ReportExport(
            report: report,
            items: onlyVisible ? model.visibleItems : report.items,
            strataVersion: AppModel.strataVersion,
            homeDirectory: model.environment.homeDirectory
        )
        let panel = NSSavePanel()
        let name = URL(fileURLWithPath: report.repositoryPath).lastPathComponent
        panel.nameFieldStringValue = "\(name)-claude-config.\(format.fileExtension)"
        panel.allowedContentTypes = [format == .json ? .json : UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export.data(as: format).write(to: url, options: .atomic)
            dismiss()
        } catch {
            failure = "Strata couldn't save the report: \(error.localizedDescription)"
        }
    }
}
