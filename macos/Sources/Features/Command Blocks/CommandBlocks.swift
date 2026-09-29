#if os(macOS)
import AppKit
import Combine
import GhosttyKit
import SwiftUI

/// One command the shell ran, with its output, like a Warp block.
struct CommandBlock: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let output: String
    /// Nil when the shell didn't report one.
    let exitCode: Int?
    let duration: TimeInterval
    let cwd: String?
    let finished: Date

    /// Ctrl-C (130) and Ctrl-Z (148) are the user stopping it, not a failure.
    var failed: Bool {
        guard let exitCode else { return false }
        return exitCode != 0 && exitCode != 130 && exitCode != 148
    }

    var program: String {
        let words = command.split(separator: " ").map(String.init)
        let first = words.first { !$0.contains("=") && !["sudo", "env", "time", "command", "exec", "noglob"].contains($0) }
        return ((first ?? "") as NSString).lastPathComponent
    }

    /// Agents and full-screen tools produce "output" that is really their UI.
    var isInteractive: Bool {
        ["claude", "codex", "vim", "nvim", "vi", "less", "man", "top", "htop", "hermes", "ssh", "tmux", "lazygit"].contains(program)
    }

    var durationText: String {
        if duration < 1 { return String(format: "%.0f ms", duration * 1000) }
        if duration < 60 { return String(format: "%.1fs", duration) }
        let seconds = Int(duration)
        return seconds < 3600 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}

/// Keeps each pane's recent commands, captured when the shell reports that a command
/// finished (OSC 133 via Ghostty's shell integration), and raises the "fix this" chip
/// when one fails.
final class CommandBlocks: ObservableObject {
    static let shared = CommandBlocks()

    /// Bumped whenever any pane's history changes.
    @Published private(set) var version = 0
    /// The failed command a pane's chip is showing.
    @Published private(set) var failures: [ObjectIdentifier: CommandBlock] = [:]

    private var blocks: [ObjectIdentifier: [CommandBlock]] = [:]
    private var surfaces: [ObjectIdentifier: Weak<Ghostty.SurfaceView>] = [:]
    private static let limit = 200

    func blocks(for surface: Ghostty.SurfaceView) -> [CommandBlock] {
        blocks[ObjectIdentifier(surface)] ?? []
    }

    func failure(for surface: Ghostty.SurfaceView) -> CommandBlock? {
        failures[ObjectIdentifier(surface)]
    }

    func dismissFailure(on surface: Ghostty.SurfaceView) {
        failures.removeValue(forKey: ObjectIdentifier(surface))
    }

    func clear(_ surface: Ghostty.SurfaceView) {
        blocks.removeValue(forKey: ObjectIdentifier(surface))
        failures.removeValue(forKey: ObjectIdentifier(surface))
        version += 1
    }

    /// Called from Ghostty's `command_finished` action.
    func commandFinished(on surface: Ghostty.SurfaceView, exitCode: Int16, duration: UInt64) {
        // Read after the action returns, outside whatever the core is doing right now.
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let self, let surface, let (command, output) = Self.readLastCommand(surface) else { return }
            let block = CommandBlock(
                command: command,
                output: output,
                exitCode: exitCode < 0 ? nil : Int(exitCode),
                duration: TimeInterval(duration) / 1_000_000_000,
                cwd: surface.pwd,
                finished: Date())
            self.record(block, on: surface)
        }
    }

    private func record(_ block: CommandBlock, on surface: Ghostty.SurfaceView) {
        let key = ObjectIdentifier(surface)
        surfaces[key] = Weak(surface)
        var list = blocks[key] ?? []
        list.append(block)
        if list.count > Self.limit { list.removeFirst(list.count - Self.limit) }
        blocks[key] = list
        // Forget panes that have closed.
        for (id, ref) in surfaces where ref.value == nil {
            surfaces.removeValue(forKey: id)
            blocks.removeValue(forKey: id)
            failures.removeValue(forKey: id)
        }
        if block.failed && !block.isInteractive && VerticalTabsAgents.shared.info(for: surface) == nil {
            failures[key] = block
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
                if self?.failures[key]?.id == block.id { self?.failures.removeValue(forKey: key) }
            }
        } else {
            failures.removeValue(forKey: key)
        }
        version += 1
    }

    private static func readLastCommand(_ surface: Ghostty.SurfaceView) -> (String, String)? {
        guard let cSurface = surface.surface else { return nil }
        var input = ghostty_text_s()
        var output = ghostty_text_s()
        guard ghostty_surface_read_last_command(cSurface, &input, &output) else { return nil }
        defer { ghostty_surface_free_last_command(&input, &output) }
        func string(_ text: ghostty_text_s) -> String {
            guard let ptr = text.text, text.text_len > 0 else { return "" }
            return String(decoding: UnsafeRawBufferPointer(start: ptr, count: Int(text.text_len)), as: UTF8.self)
        }
        let command = string(input)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        var result = string(output)
        while result.hasSuffix("\n") || result.hasSuffix(" ") { result.removeLast() }
        return (command, AgentTools.clip(result, 200_000))
    }

    // MARK: Actions

    /// Types the command into the pane again and runs it.
    @MainActor
    func rerun(_ block: CommandBlock, in surface: Ghostty.SurfaceView) {
        guard let model = surface.surfaceModel else { return }
        model.sendText(block.command)
        model.sendKeyEvent(.init(key: .enter, action: .press, text: "\r"))
        model.sendKeyEvent(.init(key: .enter, action: .release))
        Ghostty.moveFocus(to: surface)
    }

    /// Opens an agent in a split beside the pane with the command and its output, asking it to
    /// fix the failure (or explain the output when it succeeded).
    func askAgent(_ agent: VerticalTabAgentKind, about block: CommandBlock, from surface: Ghostty.SurfaceView) {
        guard let controller = surface.window?.windowController as? TerminalController else { return }
        let lines = block.output.split(separator: "\n", omittingEmptySubsequences: false)
        let tail = lines.suffix(200).joined(separator: "\n")
        let folder = block.cwd ?? surface.pwd ?? NSHomeDirectory()
        let exit = block.exitCode.map { "exited with code \($0)" } ?? "finished"
        let cut = lines.count > 200 ? " (last 200 of \(lines.count) lines)" : ""
        let prompt: String
        if block.failed {
            prompt = """
            This command failed in \(folder):

            $ \(block.command)

            It \(exit) after \(block.durationText). Its output\(cut):

            ```
            \(tail)
            ```

            Find out why it failed and fix the problem. When you're done, run the command again to confirm it works, \
            then summarize what was wrong and what you changed.
            """
        } else {
            prompt = """
            I ran this command in \(folder):

            $ \(block.command)

            It \(exit) after \(block.durationText). Its output\(cut):

            ```
            \(tail)
            ```

            Explain what this output means and point out anything that looks wrong or worth doing next. Don't change \
            any files unless I ask.
            """
        }
        guard let file = AgentTools.writePrompt(prompt, folder: "fixes", name: "\(AgentTools.timestamp())-\(agent.rawValue).md") else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = folder
        config.initialInput = AgentTools.agentCommand(agent, promptFile: file)
        controller.newSplit(at: surface, direction: .right, baseConfig: config)
        dismissFailure(on: surface)
    }
}

/// Which tabs show the command history column.
final class CommandBlocksPanel: ObservableObject {
    static let shared = CommandBlocksPanel()
    @Published private(set) var visibleTabs: Set<ObjectIdentifier> = []

    func isVisible(_ controller: TerminalController) -> Bool {
        visibleTabs.contains(ObjectIdentifier(controller))
    }

    func toggle(_ controller: TerminalController) {
        let id = ObjectIdentifier(controller)
        if visibleTabs.contains(id) { visibleTabs.remove(id) } else { visibleTabs.insert(id) }
    }

    func show(_ controller: TerminalController) {
        visibleTabs.insert(ObjectIdentifier(controller))
    }
}
#endif
