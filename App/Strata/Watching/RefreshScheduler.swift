import Foundation
import StrataCore

/// Coalesces bursts of file changes into one rescan per affected repository after a quiet period.
@MainActor
final class RefreshScheduler {
    struct Batch: Equatable {
        var global = false
        var repositoryPaths: Set<String> = []

        var isEmpty: Bool { !global && repositoryPaths.isEmpty }
    }

    private let delay: Duration
    private let action: (Batch) -> Void
    private var pending = Batch()
    private var timer: Task<Void, Never>?

    init(delay: Duration = .milliseconds(600), action: @escaping (Batch) -> Void) {
        self.delay = delay
        self.action = action
    }

    func enqueue(_ affected: ChangeRelevance.Affected) {
        switch affected {
        case .none:
            return
        case .global:
            pending.global = true
        case .repository(let path):
            pending.repositoryPaths.insert(path)
        }
        timer?.cancel()
        timer = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func cancel() {
        timer?.cancel()
        timer = nil
        pending = Batch()
    }

    private func flush() {
        let batch = pending
        pending = Batch()
        timer = nil
        if !batch.isEmpty { action(batch) }
    }
}
