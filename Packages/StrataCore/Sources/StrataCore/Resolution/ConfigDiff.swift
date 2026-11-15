import Foundation

/// How an item's content differs between two versions: line by line for Markdown files, key by key for JSON entries.
/// Both sides are already masked, so a diff can be shown as it is.
public enum ConfigDiff: Hashable, Sendable {
    case text(TextDiff)
    case keyed([KeyChange])
    /// One side wasn't captured, or the two sides aren't the same kind of content.
    case unavailable

    public init(before: ItemContent?, after: ItemContent?) {
        switch (before, after) {
        case (.text(let old)?, .text(let new)?): self = .text(TextDiff(old: old, new: new))
        case (.text(let old)?, nil): self = .text(TextDiff(old: old, new: nil))
        case (nil, .text(let new)?): self = .text(TextDiff(old: nil, new: new))
        case (.keyed(let old)?, .keyed(let new)?): self = .keyed(KeyChange.compare(old, new))
        case (.keyed(let old)?, nil): self = .keyed(KeyChange.compare(old, []))
        case (nil, .keyed(let new)?): self = .keyed(KeyChange.compare([], new))
        default: self = .unavailable
        }
    }

    public init(_ change: ConfigChange) {
        self.init(before: change.before, after: change.after)
    }

    /// True when both sides were captured and nothing visible or masked differs, as after a move.
    public var isUnchanged: Bool {
        switch self {
        case .text(let diff): diff.addedCount == 0 && diff.removedCount == 0
        case .keyed(let changes): changes.allSatisfy { $0.kind == .unchanged }
        case .unavailable: false
        }
    }
}

/// A line diff with unchanged stretches collapsed to a few lines of context around each change.
public struct TextDiff: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case unchanged, added, removed
        }

        public let kind: Kind
        public let text: String
        /// Line number in the old version, for unchanged and removed lines.
        public let oldNumber: Int?
        /// Line number in the new version, for unchanged and added lines.
        public let newNumber: Int?
    }

    public struct Hunk: Hashable, Sendable {
        /// Unchanged lines left out before this hunk.
        public let skippedBefore: Int
        public let lines: [Line]
    }

    public let hunks: [Hunk]
    /// Unchanged lines left out after the last hunk, or every line when nothing changed.
    public let skippedAfter: Int
    public let addedCount: Int
    public let removedCount: Int

    /// `nil` means the file didn't exist on that side, so every line of the other side is added or removed.
    public init(old: String?, new: String?, context: Int = 3) {
        let before = Self.lines(old)
        let after = Self.lines(new)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in after.difference(from: before) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var lines: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < before.count || newIndex < after.count {
            if oldIndex < before.count, removed.contains(oldIndex) || newIndex == after.count {
                lines.append(Line(kind: .removed, text: before[oldIndex], oldNumber: oldIndex + 1, newNumber: nil))
                oldIndex += 1
            } else if newIndex < after.count, inserted.contains(newIndex) || oldIndex == before.count {
                lines.append(Line(kind: .added, text: after[newIndex], oldNumber: nil, newNumber: newIndex + 1))
                newIndex += 1
            } else {
                lines.append(Line(kind: .unchanged, text: after[newIndex], oldNumber: oldIndex + 1, newNumber: newIndex + 1))
                oldIndex += 1
                newIndex += 1
            }
        }

        var windows: [ClosedRange<Int>] = []
        for index in lines.indices where lines[index].kind != .unchanged {
            let window = max(0, index - context)...min(lines.count - 1, index + context)
            if let last = windows.last, window.lowerBound <= last.upperBound + 1 {
                windows[windows.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                windows.append(window)
            }
        }

        var cursor = 0
        var hunks: [Hunk] = []
        for window in windows {
            hunks.append(Hunk(skippedBefore: window.lowerBound - cursor, lines: Array(lines[window])))
            cursor = window.upperBound + 1
        }
        self.hunks = hunks
        self.skippedAfter = lines.count - cursor
        self.addedCount = inserted.count
        self.removedCount = removed.count
    }

    /// Splits text into lines, without a phantom empty line after a final newline. Swift treats `\r\n` as one
    /// character, so splitting on newline characters handles both line endings.
    static func lines(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}

/// One key of a JSON entry compared across two versions.
public struct KeyChange: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case unchanged, added, removed, changed
    }

    public let path: String
    public let kind: Kind
    public let before: String?
    public let after: String?
    /// True when the value changed but the mask hides the difference, so both sides look the same.
    public let changedBehindMask: Bool

    public var id: String { path }

    /// Every key from both versions, in the new version's order, with removed keys placed after their old neighbour.
    static func compare(_ old: [KeyedValue], _ new: [KeyedValue]) -> [KeyChange] {
        let oldByPath = Dictionary(old.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let newByPath = Dictionary(new.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        var order = new.map(\.path)
        for (index, value) in old.enumerated() where newByPath[value.path] == nil {
            let neighbour = index > 0 ? order.firstIndex(of: old[index - 1].path) : nil
            order.insert(value.path, at: neighbour.map { $0 + 1 } ?? (index == 0 ? 0 : order.count))
        }

        return order.map { path in
            let was = oldByPath[path]
            let now = newByPath[path]
            let kind: Kind
            var hidden = false
            switch (was, now) {
            case (nil, _): kind = .added
            case (_, nil): kind = .removed
            case let (was?, now?) where was.display != now.display: kind = .changed
            case let (was?, now?) where was.fingerprint != now.fingerprint:
                kind = .changed
                hidden = true
            default: kind = .unchanged
            }
            return KeyChange(path: path, kind: kind, before: was?.display, after: now?.display, changedBehindMask: hidden)
        }
    }
}
