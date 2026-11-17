import AppKit
import StrataCore
import SwiftUI

/// Shows exactly what a wrong-result report will say before the browser opens it as a GitHub issue. Strata sends nothing.
struct ReportWrongResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: WrongResultReport

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Report a Wrong Result")
                        .font(.title3.weight(.semibold))
                    Text(
                        "Your browser opens a new GitHub issue with this text filled in. Home folder paths are shortened to ~ "
                            + "and anything that looks like a secret is masked. Nothing is sent until you submit it on GitHub, "
                            + "and you can edit it there first."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(report.title)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(report.body)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("wrongResultBody")
                }
                .padding(20)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open in Browser") {
                    NSWorkspace.shared.open(report.url)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("openWrongResultReport")
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 520)
    }
}

extension AppModel {
    /// Selects the item and shows the GitHub issue text for reporting that Strata got it wrong.
    func reportWrongResult(_ item: ConfigItem) {
        guard let report = selectedReport else { return }
        reveal(item.id)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "unknown") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        wrongResultReport = WrongResultReport(
            item: item,
            in: report,
            strataVersion: version,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            homeDirectory: environment.homeDirectory
        )
    }
}
