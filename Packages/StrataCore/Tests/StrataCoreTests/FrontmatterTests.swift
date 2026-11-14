@testable import StrataCore
import XCTest

final class FrontmatterTests: XCTestCase {
    func testParsesScalarsQuotesAndBooleans() throws {
        let document = """
        ---
        name: deploy
        description: "Ship the \\"current\\" branch"
        model: 'opus'
        disable-model-invocation: true
        user-invocable: no
        ---
        Body text
        """
        let (frontmatter, body) = try Frontmatter.parse(document: document)
        XCTAssertEqual(frontmatter.string("name"), "deploy")
        XCTAssertEqual(frontmatter.string("description"), "Ship the \"current\" branch")
        XCTAssertEqual(frontmatter.string("model"), "opus")
        XCTAssertEqual(frontmatter.bool("disable-model-invocation"), true)
        XCTAssertEqual(frontmatter.bool("user-invocable"), false)
        XCTAssertEqual(body, "Body text")
        XCTAssertEqual(frontmatter.orderedKeys, ["name", "description", "model", "disable-model-invocation", "user-invocable"])
    }

    func testParsesInlineAndBlockLists() throws {
        let document = """
        ---
        allowed-tools: [Read, "Grep", Bash(git *)]
        paths:
          - src/**/*.ts
          - "docs/*.md"
        ---
        """
        let (frontmatter, _) = try Frontmatter.parse(document: document)
        XCTAssertEqual(frontmatter.list("allowed-tools"), ["Read", "Grep", "Bash(git *)"])
        XCTAssertEqual(frontmatter.list("paths"), ["src/**/*.ts", "docs/*.md"])
    }

    func testCommaSeparatedStringReadsAsList() throws {
        let (frontmatter, _) = try Frontmatter.parse(document: "---\ntools: Read, Grep, Glob\n---\n")
        XCTAssertEqual(frontmatter.list("tools"), ["Read", "Grep", "Glob"])
    }

    func testParsesBlockScalars() throws {
        let document = """
        ---
        description: |
          First line
          Second line
        when_to_use: >
          Folded
          text
        ---
        """
        let (frontmatter, _) = try Frontmatter.parse(document: document)
        XCTAssertEqual(frontmatter.string("description"), "First line\nSecond line")
        XCTAssertEqual(frontmatter.string("when_to_use"), "Folded text")
    }

    func testNestedMapIsKeptAsText() throws {
        let document = """
        ---
        name: x
        hooks:
          PreToolUse:
            - matcher: Bash
        ---
        """
        let (frontmatter, _) = try Frontmatter.parse(document: document)
        XCTAssertEqual(frontmatter.string("name"), "x")
        XCTAssertNotNil(frontmatter["hooks"])
    }

    func testDocumentWithoutFrontmatter() throws {
        let (frontmatter, body) = try Frontmatter.parse(document: "# Title\nText")
        XCTAssertEqual(frontmatter, .empty)
        XCTAssertEqual(body, "# Title\nText")
    }

    func testUnterminatedFrontmatterThrows() {
        XCTAssertThrowsError(try Frontmatter.parse(document: "---\nname: x\nno closing line"))
    }

    func testHandlesByteOrderMarkAndWindowsLineEndings() throws {
        let (frontmatter, body) = try Frontmatter.parse(document: "\u{FEFF}---\r\nname: x\r\n---\r\nBody")
        XCTAssertEqual(frontmatter.string("name"), "x")
        XCTAssertEqual(body, "Body")
    }
}
