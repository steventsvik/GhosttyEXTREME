#if os(macOS)
import Foundation

/// Reads an agent's input box off its screen, to know whether a message can be typed in.
///
/// GhosttyEXTREME only ever types into an agent that's sitting at an empty input box. The
/// hooks can say an agent is ready while it shows something else (Claude Code's "trust this
/// folder?" question, a permission prompt, a menu), and typing into those would pick an
/// option. So the box itself has to be on screen:
/// - Claude Code: a `❯` (or `>`) line between two horizontal rules.
/// - Codex: a `›` line followed by its status line ("Context 12% used", "? for shortcuts").
enum AgentInputBox {
    enum State: Equatable {
        /// The box is there and empty (or showing its placeholder).
        case empty
        /// The box is there with text the user started typing.
        case typed(String)
    }

    /// Placeholders the agents show in an empty box.
    private static let placeholders = [#"^Try ""#, #"^Ask Codex to do anything"#, #"^Find and fix a bug"#,
                                       #"^Explain this codebase"#, #"^Write tests for"#, #"^Improve documentation"#,
                                       #"^Summarize recent commits"#, #"^Implement \{feature\}"#]

    static func parse(_ screen: String) -> State? {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Only the bottom of the screen: the box is always at the bottom.
        let tail = Array(lines.suffix(40))
        func isRule(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 10 && trimmed.allSatisfy { $0 == "─" || $0 == "━" }
        }
        for index in tail.indices.reversed() {
            let line = tail[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Claude Code.
            if let content = strip(trimmed, prompts: ["❯", ">"]) {
                let above = tail[..<index].last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                let below = tail[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if let above, let below, isRule(above) && isRule(below) { return state(content) }
            }
            // Codex.
            if let content = strip(trimmed, prompts: ["›"]) {
                let below = tail[(index + 1)...].prefix(3).joined(separator: "\n")
                if below.contains("Context ") || below.contains("? for shortcuts") || below.contains("context left") {
                    return state(content)
                }
            }
        }
        return nil
    }

    private static func strip(_ line: String, prompts: [String]) -> String? {
        for prompt in prompts where line.hasPrefix(prompt) {
            var rest = Substring(line.dropFirst(prompt.count))
            // Codex's animated logo can draw braille dots over the box's first column.
            let first = rest.first
            guard first == nil || first == " " || first == "\u{00A0}" || first.map(isBraille) == true else { continue }
            rest = rest.drop { $0 == " " || $0 == "\u{00A0}" || isBraille($0) }
            let content = String(rest).trimmingCharacters(in: .whitespaces)
            // A selected menu option ("1. Yes, proceed"), never an input box.
            if content.range(of: #"^[1-9]\.\s"#, options: .regularExpression) != nil { return nil }
            return content
        }
        return nil
    }

    private static func isBraille(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x2800...0x28FF).contains($0.value) }
    }

    private static func state(_ content: String) -> State {
        if content.isEmpty { return .empty }
        if placeholders.contains(where: { content.range(of: $0, options: .regularExpression) != nil }) { return .empty }
        return .typed(content)
    }
}
#endif
