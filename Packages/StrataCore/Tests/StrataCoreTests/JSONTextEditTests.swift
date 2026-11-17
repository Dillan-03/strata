import Foundation
import StrataCore
import XCTest

final class JSONTextEditTests: XCTestCase {
    private let servers = """
    {
      "numStartups": 12,
      "mcpServers": {
        "alpha": { "command": "a" },
        "beta": {
          "type": "http",
          "url": "https://example.com/mcp"
        },
        "gamma": { "command": "g" }
      },
      "projects": {
        "/Users/me/code/app.v2": {
          "mcpServers": { "local": { "command": "l" } },
          "allowedTools": []
        }
      }
    }
    """

    private func parsed(_ text: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    func testRemovingAMiddleMemberLeavesEveryOtherByte() throws {
        let (text, removed) = try JSONTextEdit.removeMember(at: ["mcpServers", "beta"], in: servers)
        XCTAssertTrue(removed.hasPrefix("\"beta\": {"))
        XCTAssertTrue(removed.hasSuffix("}"))
        XCTAssertEqual(text, servers.replacingOccurrences(of: removed + ",\n    ", with: ""))
        XCTAssertNil((try parsed(text)["mcpServers"] as? NSDictionary)?["beta"])
    }

    func testRemovingTheLastMemberTakesThePrecedingComma() throws {
        let (text, removed) = try JSONTextEdit.removeMember(at: ["mcpServers", "gamma"], in: servers)
        XCTAssertEqual(removed, "\"gamma\": { \"command\": \"g\" }")
        XCTAssertEqual(text, servers.replacingOccurrences(of: ",\n    " + removed, with: ""))
        XCTAssertNoThrow(try parsed(text))
    }

    func testRemovingTheOnlyMemberLeavesAnEmptyObject() throws {
        let (text, _) = try JSONTextEdit.removeMember(at: ["projects", "/Users/me/code/app.v2", "mcpServers", "local"], in: servers)
        XCTAssertTrue(text.contains("\"mcpServers\": {},"), "Keys containing dots and slashes are matched whole")
        XCTAssertNoThrow(try parsed(text))
    }

    func testInsertingTheRemovedMemberRestoresTheContent() throws {
        for path in [["mcpServers", "alpha"], ["mcpServers", "beta"], ["mcpServers", "gamma"], ["projects", "/Users/me/code/app.v2", "mcpServers", "local"]] {
            let (removedText, removed) = try JSONTextEdit.removeMember(at: path, in: servers)
            let restored = try JSONTextEdit.insertMember(removed, intoObjectAt: Array(path.dropLast()), in: removedText)
            XCTAssertEqual(try parsed(restored), try parsed(servers), "\(path)")
        }
        let (withoutLast, last) = try JSONTextEdit.removeMember(at: ["mcpServers", "gamma"], in: servers)
        XCTAssertEqual(try JSONTextEdit.insertMember(last, intoObjectAt: ["mcpServers"], in: withoutLast), servers, "Undoing the last member is exact")
    }

    func testReplacingAValue() throws {
        let settings = "{\n  \"enabledPlugins\": {\n    \"formatter@acme\": true,\n    \"linter@acme\": true\n  }\n}\n"
        let (text, old) = try JSONTextEdit.replaceValue(at: ["enabledPlugins", "formatter@acme"], with: "false", in: settings)
        XCTAssertEqual(old, "true")
        XCTAssertEqual(text, settings.replacingOccurrences(of: "\"formatter@acme\": true", with: "\"formatter@acme\": false"))
        XCTAssertEqual(JSONTextEdit.valueText(at: ["enabledPlugins", "formatter@acme"], in: text), "false")
    }

    func testEscapedKeysAndStringsAreHandled() throws {
        let text = #"{"a\"b": "x}\\", "c": [1, {"d": "]"}], "e": null}"#
        XCTAssertEqual(JSONTextEdit.valueText(at: [#"a"b"#], in: text), #""x}\\""#)
        let (removed, _) = try JSONTextEdit.removeMember(at: ["c"], in: text)
        XCTAssertEqual(removed, #"{"a\"b": "x}\\", "e": null}"#)
    }

    func testMissingAndMalformed() {
        XCTAssertNil(JSONTextEdit.valueText(at: ["mcpServers", "delta"], in: servers))
        XCTAssertThrowsError(try JSONTextEdit.removeMember(at: ["mcpServers", "delta"], in: servers)) { error in
            XCTAssertEqual(error as? JSONTextEdit.Failure, .notFound)
        }
        XCTAssertThrowsError(try JSONTextEdit.removeMember(at: ["numStartups", "x"], in: servers)) { error in
            XCTAssertEqual(error as? JSONTextEdit.Failure, .notFound, "A path through a number isn't an object")
        }
        XCTAssertThrowsError(try JSONTextEdit.removeMember(at: ["a"], in: #"{"a": 1"#)) { error in
            XCTAssertEqual(error as? JSONTextEdit.Failure, .malformed)
        }
    }
}
