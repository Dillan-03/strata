@testable import Strata
import StrataCore
import XCTest

@MainActor
final class RefreshSchedulerTests: XCTestCase {
    func testBurstsAreCoalescedIntoOneBatch() async throws {
        var batches: [RefreshScheduler.Batch] = []
        let scheduler = RefreshScheduler(delay: .milliseconds(150)) { batches.append($0) }

        scheduler.enqueue(.repository("/repo/a"))
        scheduler.enqueue(.repository("/repo/a"))
        scheduler.enqueue(.repository("/repo/b"))
        try await Task.sleep(for: .milliseconds(50))
        scheduler.enqueue(.global)
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(batches, [RefreshScheduler.Batch(global: true, repositoryPaths: ["/repo/a", "/repo/b"])])
    }

    func testIrrelevantChangesNeverFire() async throws {
        var fired = false
        let scheduler = RefreshScheduler(delay: .milliseconds(50)) { _ in fired = true }

        scheduler.enqueue(.none)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(fired)
    }

    func testCancelDropsPendingChanges() async throws {
        var fired = false
        let scheduler = RefreshScheduler(delay: .milliseconds(100)) { _ in fired = true }

        scheduler.enqueue(.global)
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(fired)
    }
}

final class FolderWatcherTests: XCTestCase {
    func testReportsAFileWrittenInAWatchedFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("strata-watch-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let seen = expectation(description: "change reported")
        seen.assertForOverFulfill = false
        let target = folder.appendingPathComponent("CLAUDE.md").path
        let watcher = FolderWatcher(paths: [folder.path], latency: 0.1) { paths in
            if paths.contains(where: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == target }) {
                seen.fulfill()
            }
        }
        watcher.start()
        defer { watcher.stop() }

        Thread.sleep(forTimeInterval: 0.5)
        try Data("# Hello".utf8).write(to: URL(fileURLWithPath: target))

        wait(for: [seen], timeout: 10)
    }

    func testFileWatcherSurvivesAtomicReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("strata-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(".claude.json")
        try Data("{}".utf8).write(to: file)

        let first = expectation(description: "first change")
        let second = expectation(description: "change after replacement")
        let counter = Counter()
        let watcher = FileWatcher(url: file) {
            switch counter.increment() {
            case 1: first.fulfill()
            case 3: second.fulfill()
            default: break
            }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)

        try Data(#"{"a":1}"#.utf8).write(to: file, options: .atomic)
        wait(for: [first], timeout: 5)
        Thread.sleep(forTimeInterval: 0.6)
        try Data(#"{"a":2}"#.utf8).write(to: file, options: .atomic)
        try Data(#"{"a":3}"#.utf8).write(to: file, options: .atomic)
        wait(for: [second], timeout: 5)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
