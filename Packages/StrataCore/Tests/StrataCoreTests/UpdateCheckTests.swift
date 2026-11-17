import Foundation
import StrataCore
import XCTest

final class UpdateCheckTests: XCTestCase {
    private let current = SemanticVersion("0.2.0")!

    private func reply(_ status: Int = 200, headers: [String: String] = [:], json: [String: Any]) throws -> HTTPReply {
        HTTPReply(status: status, headers: headers, body: try JSONSerialization.data(withJSONObject: json))
    }

    func testParsesVersions() {
        XCTAssertEqual(SemanticVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("1.2.3-beta.1+build.7")?.description, "1.2.3-beta.1")
        XCTAssertEqual(SemanticVersion(" 0.10.0 ")?.minor, 10)
        for bad in ["", "1.2", "1.2.3.4", "01.2.3", "1.2.x", "1.2.3-", "v", "１.2.3", "-1.2.3"] {
            XCTAssertNil(SemanticVersion(bad), bad)
        }
    }

    func testOrdersBySemanticVersioning() {
        let ordered = ["0.9.9", "0.10.0-beta.1", "0.10.0", "0.10.1", "1.0.0"].compactMap(SemanticVersion.init)
        XCTAssertEqual(ordered.count, 5)
        XCTAssertEqual(ordered.shuffled().sorted(), ordered)
        XCTAssertEqual(SemanticVersion("1.0.0+a"), SemanticVersion("1.0.0+b"))
    }

    func testNewerReleaseIsAvailableWithItsReleasePage() throws {
        let result = UpdateChecker.result(for: try reply(json: ["tag_name": "v0.3.0", "draft": false, "prerelease": false]), current: current)
        XCTAssertEqual(result, .available(SemanticVersion("0.3.0")!, releaseNotes: URL(string: "https://github.com/Dillan-03/strata/releases/tag/v0.3.0")!))
    }

    func testSameOrOlderReleaseIsUpToDate() throws {
        for tag in ["v0.2.0", "v0.1.0"] {
            XCTAssertEqual(UpdateChecker.result(for: try reply(json: ["tag_name": tag]), current: current), .upToDate(current), tag)
        }
    }

    func testDraftsAndPreReleasesAreIgnored() throws {
        let replies = [
            try reply(json: ["tag_name": "v0.3.0", "draft": true]),
            try reply(json: ["tag_name": "v0.3.0", "prerelease": true]),
            try reply(json: ["tag_name": "v0.3.0-beta.1"]),
        ]
        for reply in replies {
            XCTAssertEqual(UpdateChecker.result(for: reply, current: current), .upToDate(current))
        }
    }

    func testTheReleasePageNeverComesFromTheResponse() throws {
        let hostile = try reply(json: ["tag_name": "v0.3.0", "html_url": "https://example.com/strata.pkg"])
        guard case .available(_, let releaseNotes) = UpdateChecker.result(for: hostile, current: current) else { return XCTFail("Expected an update") }
        XCTAssertEqual(releaseNotes.host, "github.com")
        XCTAssertTrue(releaseNotes.path.hasPrefix("/Dillan-03/strata/releases/tag/"))
    }

    func testMalformedResponses() throws {
        let bodies: [Data] = [
            Data("not json".utf8),
            Data("[]".utf8),
            try JSONSerialization.data(withJSONObject: ["name": "Strata 0.3.0"]),
            try JSONSerialization.data(withJSONObject: ["tag_name": 3]),
            try JSONSerialization.data(withJSONObject: ["tag_name": "latest"]),
        ]
        for body in bodies {
            XCTAssertEqual(UpdateChecker.result(for: HTTPReply(status: 200, body: body), current: current), .failed(.malformed))
        }
    }

    func testStatusCodes() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let limited = HTTPReply(status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"])
        XCTAssertEqual(UpdateChecker.result(for: limited, current: current), .failed(.rateLimited(until: reset)))
        XCTAssertEqual(UpdateChecker.result(for: HTTPReply(status: 429), current: current), .failed(.rateLimited(until: nil)))
        XCTAssertEqual(UpdateChecker.result(for: HTTPReply(status: 403), current: current), .failed(.unexpectedStatus(403)))
        XCTAssertEqual(UpdateChecker.result(for: HTTPReply(status: 404), current: current), .failed(.noRelease))
        XCTAssertEqual(UpdateChecker.result(for: HTTPReply(status: 500), current: current), .failed(.unexpectedStatus(500)))
    }

    func testEveryFailureHasAMessage() {
        let failures: [UpdateCheckFailure] = [
            .unreachable, .rateLimited(until: Date()), .rateLimited(until: nil), .noRelease, .unexpectedStatus(502), .malformed, .unknownCurrentVersion("dev"),
        ]
        for failure in failures {
            XCTAssertFalse(failure.message.isEmpty, "\(failure)")
        }
    }

    func testCheckMakesOneRequestToTheLatestReleaseAPI() async throws {
        let requests = Requests()
        let body = try JSONSerialization.data(withJSONObject: ["tag_name": "v0.2.0"])
        let checker = UpdateChecker { url in
            await requests.record(url)
            return HTTPReply(status: 200, body: body)
        }
        let result = await checker.check(currentVersion: "0.2.0")
        XCTAssertEqual(result, .upToDate(current))
        let urls = await requests.urls
        XCTAssertEqual(urls, [URL(string: "https://api.github.com/repos/Dillan-03/strata/releases/latest")!])
    }

    func testCheckReportsUnreachableAndAnUnreadableCurrentVersion() async {
        struct Offline: Error {}
        let offline = UpdateChecker { _ in throw Offline() }
        let unreachable = await offline.check(currentVersion: "0.2.0")
        XCTAssertEqual(unreachable, .failed(.unreachable))
        let unknown = await offline.check(currentVersion: "dev")
        XCTAssertEqual(unknown, .failed(.unknownCurrentVersion("dev")))
    }
}

private actor Requests {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}
