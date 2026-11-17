@testable import StrataCore
import XCTest

final class WrongResultReportTests: XCTestCase {
    func testTheReportDescribesTheItemWithHomePathsShortenedAndSecretsMasked() throws {
        let fixture = try Fixture()
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Personal deploy"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo deploy"))
        let report = fixture.inspect()
        var item = try XCTUnwrap(report.items.first { $0.kind == .skill && $0.scope == .project })
        item.explanation.append("Token sk-ant-api03-SECRETSECRETSECRET was in \(fixture.home.path)/notes.txt")

        let wrong = WrongResultReport(item: item, in: report, strataVersion: "0.3.0 (3)", macOSVersion: "15.8", homeDirectory: fixture.home)
        XCTAssertTrue(wrong.title.hasPrefix("[Bug] Wrong result for skill"), "The issue-title check requires a [Bug] prefix")
        XCTAssertTrue(wrong.body.contains("Status: Overridden"))
        XCTAssertTrue(wrong.body.contains("Competing definitions"))
        XCTAssertTrue(wrong.body.contains("~/notes.txt"))
        XCTAssertTrue(wrong.body.contains("Strata 0.3.0 (3)"))
        XCTAssertFalse(wrong.body.contains(fixture.home.path), "The home folder is shortened to ~")
        XCTAssertFalse(wrong.body.contains("SECRETSECRET"))
        XCTAssertFalse(wrong.url.absoluteString.contains("SECRETSECRET"))
        XCTAssertEqual(wrong.url.host, "github.com")
        XCTAssertEqual(wrong.url.path, "/Dillan-03/strata/issues/new")
        let body = URLComponents(url: wrong.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(body, wrong.body, "The body survives the link intact")
    }

    func testAmpersandsAndHashesDontBreakTheLink() {
        XCTAssertEqual(WrongResultReport.encode("a&b=c+d#e f"), "a%26b%3Dc%2Bd%23e%20f")
    }

    func testALongBodyIsTrimmedToFitAGitHubLink() {
        let long = String(repeating: "Ünïcode explanation line that needs percent-encoding.\n", count: 400)
        let fitted = WrongResultReport.fitting(long)
        XCTAssertLessThanOrEqual(WrongResultReport.encode(fitted).count, WrongResultReport.maximumEncodedBodyLength)
        XCTAssertTrue(fitted.hasSuffix("Add anything missing by hand._"))
        XCTAssertEqual(WrongResultReport.fitting("short"), "short", "A short body is left alone")
    }
}
