@testable import StrataCore
import XCTest

final class ImportParserTests: XCTestCase {
    func testFindsImportsInProse() {
        let text = "See @README for an overview and @package.json for scripts.\n- git workflow @docs/git-instructions.md"
        XCTAssertEqual(ImportParser.imports(in: text), ["README", "package.json", "docs/git-instructions.md"])
    }

    func testSkipsCodeSpansAndFencedBlocks() {
        let text = """
        Keep `@README` literal.
        ```
        @inside-fence.md
        ```
        ~~~
        @also-inside.md
        ~~~
        @outside.md
        """
        XCTAssertEqual(ImportParser.imports(in: text), ["outside.md"])
    }

    func testEscapedSpacesAreKeptAndQuotedPathsIgnored() {
        let text = "- API conventions @Design\\ Docs/api-conventions.md\n- \"@quoted/path.md\""
        XCTAssertEqual(ImportParser.imports(in: text), ["Design Docs/api-conventions.md"])
    }

    func testEmailAddressesAreNotImports() {
        XCTAssertEqual(ImportParser.imports(in: "Contact dev@example.com"), [])
    }

    func testTrailingPunctuationIsDropped() {
        XCTAssertEqual(ImportParser.imports(in: "Read @docs/guide.md, then @CHANGELOG."), ["docs/guide.md", "CHANGELOG"])
    }

    func testHomeAndParentRelativeImports() {
        XCTAssertEqual(ImportParser.imports(in: "@~/.claude/mine.md and @../shared/rules.md"), ["~/.claude/mine.md", "../shared/rules.md"])
    }

    func testResolvesRelativeToTheImportingFile() {
        let file = URL(fileURLWithPath: "/repo/docs/CLAUDE.md")
        let home = URL(fileURLWithPath: "/Users/dev")
        XCTAssertEqual(ImportParser.resolve("guide.md", from: file, home: home).path, "/repo/docs/guide.md")
        XCTAssertEqual(ImportParser.resolve("../README", from: file, home: home).path, "/repo/README")
        XCTAssertEqual(ImportParser.resolve("~/.claude/x.md", from: file, home: home).path, "/Users/dev/.claude/x.md")
        XCTAssertEqual(ImportParser.resolve("/etc/notes.md", from: file, home: home).path, "/etc/notes.md")
    }

    func testDistinguishesPathsFromMentions() {
        XCTAssertTrue(ImportParser.looksLikeFilePath("docs/a.md"))
        XCTAssertTrue(ImportParser.looksLikeFilePath("README.md"))
        XCTAssertFalse(ImportParser.looksLikeFilePath("someone"))
    }
}
