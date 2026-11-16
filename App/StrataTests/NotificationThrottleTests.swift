@testable import Strata
import XCTest

final class NotificationThrottleTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testABurstOfEditsBecomesOneAnnouncement() {
        var throttle = NotificationThrottle(settle: 5, maximumWait: 30)
        XCTAssertEqual(throttle.observe(["a"], at: at(0)), at(5))
        XCTAssertEqual(throttle.observe(["a", "b"], at: at(2)), at(7), "A new change pushes the announcement back")
        XCTAssertEqual(throttle.observe(["a", "b", "c"], at: at(4)), at(9))

        XCTAssertNil(throttle.due(["a", "b", "c"], at: at(8)), "Not due until the burst settles")
        XCTAssertEqual(throttle.due(["a", "b", "c"], at: at(9)), ["a", "b", "c"])
        XCTAssertNil(throttle.due(["a", "b", "c"], at: at(60)), "Announced changes aren't announced again")
    }

    func testAStreamOfEditsIsAnnouncedAfterTheMaximumWait() {
        var throttle = NotificationThrottle(settle: 5, maximumWait: 30)
        var ids: [String] = []
        for second in stride(from: 0, through: 40, by: 4) {
            ids.append("change-\(second)")
            _ = throttle.observe(ids, at: at(TimeInterval(second)))
        }
        XCTAssertEqual(throttle.dueDate, at(30), "Edits every 4 seconds can't hold the announcement past 30 seconds")
    }

    func testEditingAnAnnouncedChangeAgainStaysQuiet() {
        var throttle = NotificationThrottle(settle: 5, maximumWait: 30)
        _ = throttle.observe(["skill"], at: at(0))
        XCTAssertEqual(throttle.due(["skill"], at: at(5)), ["skill"])

        XCTAssertNil(throttle.observe(["skill"], at: at(20)), "Still the same pending change")
    }

    func testAReviewedChangeCanBeAnnouncedAgain() {
        var throttle = NotificationThrottle(settle: 5, maximumWait: 30)
        _ = throttle.observe(["skill"], at: at(0))
        XCTAssertEqual(throttle.due(["skill"], at: at(5)), ["skill"])

        XCTAssertNil(throttle.observe([], at: at(10)), "Reviewed: nothing pending")
        XCTAssertEqual(throttle.observe(["skill"], at: at(20)), at(25), "Edited again after the review")
    }

    func testReviewingBeforeTheAnnouncementCancelsIt() {
        var throttle = NotificationThrottle(settle: 5, maximumWait: 30)
        _ = throttle.observe(["skill"], at: at(0))
        XCTAssertNil(throttle.observe([], at: at(2)))
        XCTAssertNil(throttle.due([], at: at(10)))
    }
}
