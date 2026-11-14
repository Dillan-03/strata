import Foundation
import StrataCore
import XCTest

/// Files Strata can't or won't read must produce a diagnostic, never a crash, a hang or a silently missing item.
final class FileHandlingTests: XCTestCase {
    func testOversizedFileIsReportedAndNotRead() throws {
        let fixture = try Fixture()
        let url = try fixture.write(".claude/settings.json", in: fixture.repository, "")
        let padding = String(repeating: " ", count: 2 * 1024 * 1024)
        try Data(#"{"model": "opus"}"#.utf8 + Data(padding.utf8)).write(to: url)

        let report = fixture.inspect()
        let diagnostic = try XCTUnwrap(report.diagnostics.first { $0.code == .unreadableFile && $0.paths.contains { $0.hasSuffix("/.claude/settings.json") } })
        XCTAssertTrue(diagnostic.detail.contains("larger than Strata reads"), diagnostic.detail)
        XCTAssertTrue(report.items(.setting, named: "model").isEmpty)
    }

    func testFileThatIsNotUTF8IsReported() throws {
        let fixture = try Fixture()
        let url = try fixture.write(".mcp.json", in: fixture.repository, "")
        try Data([0xFF, 0xFE, 0x7B, 0x00, 0x7D, 0x00]).write(to: url)

        let report = fixture.inspect()
        XCTAssertTrue(report.diagnostics.contains { $0.code == .unreadableFile && $0.detail.contains("UTF-8") })
    }

    func testFileWithoutReadPermissionIsReported() throws {
        try XCTSkipIf(getuid() == 0, "root can read a file whatever its permissions")
        let fixture = try Fixture()
        let url = try fixture.write(".claude/settings.json", in: fixture.repository, #"{"model": "opus"}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let report = fixture.inspect()
        XCTAssertTrue(report.diagnostics.contains { $0.code == .unreadableFile && $0.paths.contains { $0.hasSuffix("/.claude/settings.json") } })
    }

    func testUnterminatedFrontmatterIsReported() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/broken/SKILL.md", in: fixture.repository, "---\ndescription: The closing marker is missing\n")

        XCTAssertTrue(fixture.inspect().hasDiagnostic(.malformedFrontmatter))
    }

    func testSymlinkLoopDoesNotHangOrDuplicate() throws {
        let fixture = try Fixture()
        let commands = fixture.repository.appendingPathComponent(".claude/commands")
        try fixture.write("ship.md", in: commands, "---\ndescription: Ship it\n---\n")
        try FileManager.default.createSymbolicLink(at: commands.appendingPathComponent("again"), withDestinationURL: commands)

        let report = fixture.inspect()
        XCTAssertEqual(report.items(.command, named: "ship").count, 1)
    }
}
