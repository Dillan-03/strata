import StrataCore
import XCTest

final class CrossRepositorySearchTests: XCTestCase {
    private var fixture: Fixture!
    private var reports: [(Repository.ID, InspectionReport)] = []
    private let first = UUID()
    private let second = UUID()

    override func setUpWithError() throws {
        fixture = try Fixture()
        let other = fixture.home.appendingPathComponent("code/other")
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.home, Fixture.skill(description: "Personal deploy"))
        try fixture.write(".claude/skills/deploy/SKILL.md", in: fixture.repository, Fixture.skill(description: "Repo deploy"))
        try fixture.write(".claude/skills/lint/SKILL.md", in: other, Fixture.skill(description: "Lint the other repo"))
        let inspector = Inspector(environment: fixture.environment)
        reports = [(first, inspector.inspect(fixture.repository)), (second, inspector.inspect(other))]
    }

    override func tearDown() {
        fixture = nil
        reports = []
    }

    func testFindsItemsInEveryRepositoryAndListsSharedOnesOnce() throws {
        let results = CrossRepositorySearch.results(for: ItemQuery(text: "deploy"), in: reports, kinds: [.skill, .command])
        let shared = try XCTUnwrap(results.shared.first)
        XCTAssertEqual(results.shared.count, 1, "The personal skill appears in both reports but is listed once")
        XCTAssertEqual(shared.statuses[first], .effective)
        XCTAssertEqual(shared.statuses[second], .effective)
        XCTAssertEqual(results.byRepository.map(\.repositoryID), [first], "Only the first repository has its own deploy skill")
        XCTAssertEqual(results.byRepository.first?.items.first?.applicability.title, "Overridden")
    }

    func testFindsAnItemOnlyInASecondRepository() {
        let results = CrossRepositorySearch.results(for: ItemQuery(text: "lint"), in: reports, kinds: nil)
        XCTAssertTrue(results.shared.isEmpty)
        XCTAssertEqual(results.byRepository.map(\.repositoryID), [second])
        let found = results.byRepository.flatMap(\.items).map { "\($0.kind) \($0.scope) \($0.name) \($0.source.path)" }
        XCTAssertEqual(results.count, 1, "\(found)")
    }

    func testFiltersAndCategoryStillApply() {
        let overridden = CrossRepositorySearch.results(for: ItemQuery(text: "deploy", statuses: [.overridden]), in: reports, kinds: nil)
        XCTAssertEqual(overridden.count, 1)
        XCTAssertTrue(CrossRepositorySearch.results(for: ItemQuery(text: "deploy"), in: reports, kinds: [.agent]).isEmpty)
    }

    func testSearchingManyRepositoriesIsFast() {
        let template = reports[0].1
        let many = (0..<40).map { _ in (UUID(), template) }
        let start = Date()
        _ = CrossRepositorySearch.results(for: ItemQuery(text: "personal"), in: many, kinds: nil)
        // Runs on every keystroke with All Repositories on. The limit leaves room for slow CI runners.
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25)
    }
}
