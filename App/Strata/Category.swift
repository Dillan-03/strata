import StrataCore
import SwiftUI

/// The groups the item list can show, matching the toolbar picker.
enum Category: String, CaseIterable, Identifiable {
    case all
    case skills
    case agents
    case mcp
    case plugins
    case hooks
    case instructions
    case settings
    case issues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .skills: "Skills"
        case .agents: "Agents"
        case .mcp: "MCP"
        case .plugins: "Plugins"
        case .hooks: "Hooks"
        case .instructions: "Instructions"
        case .settings: "Settings"
        case .issues: "Issues"
        }
    }

    /// The item kinds this category lists. `nil` means every kind; `issues` lists diagnostics instead.
    var kinds: Set<ItemKind>? {
        switch self {
        case .all, .issues: nil
        case .skills: [.skill, .command]
        case .agents: [.agent]
        case .mcp: [.mcpServer]
        case .plugins: [.plugin]
        case .hooks: [.hook]
        case .instructions: [.instruction]
        case .settings: [.setting, .permission]
        }
    }

    /// ⌘1 to ⌘9, in picker order.
    var shortcut: KeyEquivalent {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }

    func includes(_ kind: ItemKind) -> Bool {
        kinds?.contains(kind) ?? true
    }
}
