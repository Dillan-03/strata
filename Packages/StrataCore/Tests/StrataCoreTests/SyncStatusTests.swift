@testable import StrataCore
import XCTest

final class SyncStatusTests: XCTestCase {
    private func change(_ timing: SessionPickup.Timing) -> ConfigChange {
        let item = ConfigItem(kind: .skill, name: "deploy", scope: .user, source: SourceLocation(path: "/home/me/.claude/skills/deploy/SKILL.md"))
        return ConfigChange(kind: .updated, item: item, previous: item, pickup: SessionPickup(timing, "", source: nil))
    }

    private func diagnostic(_ severity: Diagnostic.Severity) -> Diagnostic {
        Diagnostic(severity: severity, code: .shadowedDefinition, title: "Hidden", detail: "", itemIDs: [])
    }

    func testAnItemWithoutAChangeIsUnchangedEvenWithAConflict() {
        XCTAssertEqual(SyncStatus.of(nil, conflicts: []), .unchanged)
        XCTAssertEqual(SyncStatus.of(nil, conflicts: [diagnostic(.conflict)]), .unchanged, "Conflicts are shown elsewhere; this is about change")
    }

    func testPickedUpByItselfIsChangeDetected() {
        XCTAssertEqual(SyncStatus.of(change(.live), conflicts: []), .changeDetected)
        XCTAssertEqual(SyncStatus.of(change(.onDemand), conflicts: []), .changeDetected)
    }

    func testReloadsAndNewSessionsAreActionRequired() {
        for timing in [SessionPickup.Timing.reloadSkills, .reloadPlugins, .nextSession] {
            XCTAssertEqual(SyncStatus.of(change(timing), conflicts: []), .actionRequired(timing))
        }
    }

    func testUndocumentedPickupCantBeVerified() {
        XCTAssertEqual(SyncStatus.of(change(.unknown), conflicts: []), .unableToVerify)
    }

    func testConflictsOutrankPickup() {
        XCTAssertEqual(SyncStatus.of(change(.nextSession), conflicts: [diagnostic(.warning)]), .conflict)
        XCTAssertEqual(SyncStatus.of(change(.live), conflicts: [diagnostic(.conflict)]), .conflict)
        XCTAssertEqual(SyncStatus.of(change(.live), conflicts: [diagnostic(.info)]), .changeDetected, "Info notes aren't conflicts")
    }
}
