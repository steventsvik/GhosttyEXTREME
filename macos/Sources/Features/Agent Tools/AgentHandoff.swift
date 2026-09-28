#if os(macOS)
import AppKit

/// Passes a pane's work to another agent, with the context written into its first prompt:
/// the task, the last agent's final message and what's changed in git. The new agent opens
/// in a split beside the original so both stay visible.
enum AgentHandoff {
    enum Mode: CaseIterable {
        /// Read the changes and report problems without editing anything.
        case review
        /// Pick up the task where the previous agent stopped.
        case `continue`

        var verb: String {
            switch self {
            case .review: return "Review with"
            case .continue: return "Continue with"
            }
        }
    }

    static let targets: [VerticalTabAgentKind] = [.claude, .codex]

    static func title(_ mode: Mode, _ target: VerticalTabAgentKind) -> String {
        "\(mode.verb) \(target.displayName)"
    }

    static func handOff(from surface: Ghostty.SurfaceView,
                        in controller: TerminalController,
                        to target: VerticalTabAgentKind,
                        mode: Mode) {
        guard let folder = surface.pwd else { return }
        let info = VerticalTabsAgents.shared.info(for: surface)
        let source = info?.kind
        // Git and the transcript can take a moment on big repos; gather them off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let prompt = makePrompt(mode: mode, source: source, task: info?.task,
                                    lastMessage: AgentTools.lastAssistantMessage(transcript: info?.transcriptPath),
                                    folder: folder)
            DispatchQueue.main.async {
                guard let file = AgentTools.writePrompt(
                    prompt, folder: "handoffs", name: "\(AgentTools.timestamp())-\(target.rawValue).md") else { return }
                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = folder
                config.initialInput = AgentTools.agentCommand(target, promptFile: file)
                controller.newSplit(at: surface, direction: .right, baseConfig: config)
            }
        }
    }

    private static func makePrompt(mode: Mode, source: VerticalTabAgentKind?, task: String?,
                                   lastMessage: String?, folder: String) -> String {
        let who = source.map { "another coding agent (\($0.displayName))" } ?? "someone"
        var context: [String] = []
        if let task, !task.isEmpty { context.append("Their task was:\n\(task)") }
        if let lastMessage, !lastMessage.isEmpty {
            context.append("Their last message:\n\(AgentTools.clip(lastMessage, 4000))")
        }
        if AgentTools.repoRoot(of: folder) != nil {
            let status = AgentTools.git(["status", "--short"], in: folder).output.trimmingCharacters(in: .newlines)
            let stat = AgentTools.git(["diff", "--stat", "HEAD"], in: folder).output.trimmingCharacters(in: .newlines)
            if status.isEmpty {
                context.append("There are no uncommitted changes; look at the most recent commits (`git log -p -3`).")
            } else {
                context.append("Uncommitted changes (git status):\n\(AgentTools.clip(status, 3000))")
                if !stat.isEmpty { context.append("Diff summary:\n\(AgentTools.clip(stat, 2000))") }
            }
        }
        let background = context.joined(separator: "\n\n")

        switch mode {
        case .review:
            return """
            You're reviewing work that \(who) just did in this folder.

            \(background)

            Review those changes: run `git diff` (and read any new files) to see exactly what changed. Look for bugs, \
            security problems, missed edge cases, and anything that doesn't match the task. List your findings from \
            most to least important, each with a file:line reference and a suggested fix. If everything looks right, \
            say so. Do not modify any files; this is a review only.
            """
        case .continue:
            return """
            You're taking over a task from \(who), who was working in this folder and stopped.

            \(background)

            First check the current state (run `git diff` and read the relevant files), then finish the task. \
            Keep what's already done unless it's wrong. When you're finished, summarize what you changed.
            """
        }
    }
}
#endif
