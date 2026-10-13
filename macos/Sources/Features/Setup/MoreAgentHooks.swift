#if os(macOS)
import Foundation

/// Live status for agents beyond Claude Code and Codex. Each has its own hook format and
/// config file; all of them run the same observer, `agent-event.py <agent> <event>`, which
/// never approves, blocks or changes anything.
///
/// Where the agent reads a folder of hook files, Tellurion writes a file of its own
/// there. Where hooks share a settings file with the user's, only our entries are added
/// or removed, and the file is backed up first.
enum MoreAgent: String, CaseIterable, Identifiable {
    case copilot, droid, kiro, gemini, antigravity, cursor, opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copilot: return "Copilot CLI"
        case .droid: return "Droid"
        case .kiro: return "Kiro CLI"
        case .gemini: return "Gemini CLI"
        case .antigravity: return "Antigravity CLI"
        case .cursor: return "Cursor CLI"
        case .opencode: return "OpenCode"
        }
    }

    /// The command that starts it, for finding whether it's installed.
    var commands: [String] {
        switch self {
        case .copilot: return ["copilot"]
        case .droid: return ["droid"]
        case .kiro: return ["kiro-cli"]
        case .gemini: return ["gemini"]
        case .antigravity: return ["agy"]
        case .cursor: return ["cursor-agent"]
        case .opencode: return ["opencode"]
        }
    }

    /// What it can report: not every agent says when it's waiting for permission.
    var reports: String {
        switch self {
        case .copilot, .droid, .gemini: return "working, needs permission, done"
        case .kiro, .antigravity, .cursor: return "working and done (it doesn't report permission prompts)"
        case .opencode: return "working, needs permission, done"
        }
    }

    /// The agent's own hook events, in the order they're written.
    var events: [(name: String, matcher: String?)] {
        switch self {
        case .copilot:
            return [("sessionStart", nil), ("userPromptSubmitted", nil), ("postToolUse", nil), ("notification", nil),
                    ("agentStop", nil), ("errorOccurred", nil), ("sessionEnd", nil)]
        case .droid:
            return [("SessionStart", nil), ("UserPromptSubmit", nil), ("PostToolUse", "*"), ("Notification", nil),
                    ("Stop", nil), ("SessionEnd", nil)]
        case .kiro:
            return [("SessionStart", nil), ("UserPromptSubmit", nil), ("PostToolUse", nil), ("Stop", nil), ("SessionEnd", nil)]
        case .gemini:
            return [("SessionStart", nil), ("BeforeAgent", nil), ("AfterTool", "*"), ("Notification", nil),
                    ("AfterAgent", nil), ("SessionEnd", nil)]
        case .antigravity:
            return [("PreInvocation", nil), ("PostToolUse", "*"), ("Stop", nil)]
        case .cursor:
            return [("sessionStart", nil), ("postToolUse", nil), ("afterFileEdit", nil), ("stop", nil), ("sessionEnd", nil)]
        case .opencode:
            return []
        }
    }

    /// The file its hooks go in.
    func file(home: String) -> URL {
        let path: String
        switch self {
        case .copilot: path = "/.copilot/hooks/ghostty-extreme.json"
        case .droid:
            // A hooks.json replaces the settings file's hooks, so never create one.
            path = FileManager.default.fileExists(atPath: home + "/.factory/hooks.json") ? "/.factory/hooks.json" : "/.factory/settings.json"
        case .kiro: path = "/.kiro/hooks/ghostty-extreme.json"
        case .gemini: path = "/.gemini/settings.json"
        case .antigravity: path = "/.gemini/config/hooks.json"
        case .cursor: path = "/.cursor/hooks.json"
        case .opencode: path = "/.config/opencode/plugins/ghostty-extreme.js"
        }
        return URL(fileURLWithPath: home + path)
    }

    /// The whole file is ours (deleted to disconnect), rather than entries in a shared one.
    var ownsFile: Bool { [.copilot, .kiro, .opencode].contains(self) }

    /// Signs of it on this Mac, besides its command.
    func isPresent(home: String, tools: [String: String]) -> Bool {
        if commands.contains(where: { tools[$0] != nil }) { return true }
        switch self {
        case .copilot: return FileManager.default.fileExists(atPath: home + "/.copilot")
        case .droid: return FileManager.default.fileExists(atPath: home + "/.factory")
        case .kiro: return FileManager.default.fileExists(atPath: home + "/.kiro")
        case .antigravity: return FileManager.default.fileExists(atPath: home + "/.gemini/antigravity-cli")
        // Cursor's and Gemini's folders also belong to their apps; only the CLI counts.
        case .gemini, .cursor, .opencode: return false
        }
    }

    func command(script: String, event: String) -> String {
        "\(script) \(rawValue) \(event)"
    }

    fileprivate func isOurs(_ command: String) -> Bool {
        command.contains("agent-event.py \(rawValue) ")
    }
}

/// Pure merging, so it can be checked on its own (like `HookConfig`).
enum MoreAgentConfig {
    /// The config with our hooks in it.
    /// `eventsAtTop`: the file keeps events at its top level instead of under "hooks"
    /// (Droid's hooks.json).
    static func connected(_ agent: MoreAgent, config: [String: Any], script: String, eventsAtTop: Bool = false) -> [String: Any] {
        let config = disconnected(agent, config: config, eventsAtTop: eventsAtTop)
        switch agent {
        case .copilot:
            var hooks: [String: Any] = [:]
            for event in agent.events {
                hooks[event.name] = [["type": "command", "bash": agent.command(script: script, event: event.name), "timeoutSec": 5]]
            }
            return ["version": 1, "hooks": hooks]
        case .kiro:
            return ["version": "v1", "hooks": agent.events.map { event in
                ["name": "ghostty-extreme-\(event.name)", "trigger": event.name, "timeout": 5, "enabled": true,
                 "action": ["type": "command", "command": agent.command(script: script, event: event.name)]] as [String: Any]
            }]
        case .droid, .gemini:
            let topLevel = eventsAtTop
            var hooks = topLevel ? config : config["hooks"] as? [String: Any] ?? [:]
            for event in agent.events {
                var handler: [String: Any] = ["type": "command", "command": agent.command(script: script, event: event.name)]
                // Gemini counts milliseconds.
                handler["timeout"] = agent == .gemini ? 5000 : 5
                if agent == .gemini { handler["name"] = "ghostty-extreme" }
                var groups = hooks[event.name] as? [[String: Any]] ?? []
                groups.append(["matcher": event.matcher ?? "", "hooks": [handler]])
                hooks[event.name] = groups
            }
            if topLevel { return hooks }
            var result = config
            result["hooks"] = hooks
            return result
        case .antigravity:
            var entry: [String: Any] = ["enabled": true]
            for event in agent.events {
                entry[event.name] = [["matcher": event.matcher ?? "", "hooks": [
                    ["type": "command", "command": agent.command(script: script, event: event.name), "timeout": 5],
                ]]]
            }
            var result = config
            result["ghostty-extreme"] = entry
            return result
        case .cursor:
            var result = config
            if result["version"] == nil { result["version"] = 1 }
            var hooks = result["hooks"] as? [String: Any] ?? [:]
            for event in agent.events {
                var list = hooks[event.name] as? [[String: Any]] ?? []
                list.append(["command": agent.command(script: script, event: event.name), "timeout": 5])
                hooks[event.name] = list
            }
            result["hooks"] = hooks
            return result
        case .opencode:
            return config
        }
    }

    /// The config without our hooks; everything else as it was.
    static func disconnected(_ agent: MoreAgent, config: [String: Any], eventsAtTop: Bool = false) -> [String: Any] {
        switch agent {
        case .copilot, .kiro, .opencode:
            return [:]
        case .antigravity:
            var result = config
            result.removeValue(forKey: "ghostty-extreme")
            return result
        case .cursor:
            var result = config
            guard var hooks = result["hooks"] as? [String: Any] else { return result }
            for (event, value) in hooks {
                let kept = (value as? [[String: Any]] ?? []).filter { !(($0["command"] as? String).map(agent.isOurs) ?? false) }
                if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
            }
            result["hooks"] = hooks
            return result
        case .droid, .gemini:
            let topLevel = eventsAtTop
            var hooks = topLevel ? config : config["hooks"] as? [String: Any] ?? [:]
            for (event, value) in hooks {
                guard var groups = value as? [[String: Any]] else { continue }
                for index in groups.indices {
                    let handlers = groups[index]["hooks"] as? [[String: Any]] ?? []
                    groups[index]["hooks"] = handlers.filter { !(($0["command"] as? String).map(agent.isOurs) ?? false) }
                }
                groups.removeAll { ($0["hooks"] as? [[String: Any]])?.isEmpty == true }
                if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
            }
            if topLevel { return hooks }
            var result = config
            if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
            return result
        }
    }

    /// Whether every one of our hooks is in the config.
    static func isConnected(_ agent: MoreAgent, config: [String: Any]) -> Bool {
        let text = (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        return agent.events.allSatisfy { text.contains("agent-event.py \(agent.rawValue) \($0.name)") }
    }
}

extension HookInstaller {
    static var moreAgentScript: String { hooksFolder.appendingPathComponent("agent-event.py").path }

    static func isConnected(_ agent: MoreAgent) -> Bool {
        let url = agent.file(home: home)
        if agent == .opencode { return FileManager.default.fileExists(atPath: url.path) }
        guard let config = try? readJSON(url) else { return false }
        return MoreAgentConfig.isConnected(agent, config: config)
    }

    static func connect(_ agent: MoreAgent) throws {
        if filesState() != .current { try installFiles() }
        let url = agent.file(home: home)
        if agent == .opencode {
            guard let source = bundled?.appendingPathComponent("opencode-plugin.js") else {
                throw Failure(message: "This build of Tellurion doesn't include the OpenCode plugin.")
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source).write(to: url, options: .atomic)
            return
        }
        let config = agent.ownsFile ? [:] : try readJSON(url)
        try writeJSON(MoreAgentConfig.connected(agent, config: config, script: moreAgentScript,
                                                eventsAtTop: url.lastPathComponent == "hooks.json" && agent == .droid), to: url)
    }

    static func disconnect(_ agent: MoreAgent) throws {
        let url = agent.file(home: home)
        if agent.ownsFile {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let config = try readJSON(url)
        try writeJSON(MoreAgentConfig.disconnected(agent, config: config,
                                                   eventsAtTop: url.lastPathComponent == "hooks.json" && agent == .droid), to: url)
    }

    /// The file's JSON, or an empty object when there's no file; throws when it isn't JSON
    /// we can safely rewrite.
    private static func readJSON(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "\(display(url)) isn't valid JSON (or has comments), so it was left alone.")
        }
        return object
    }

    private static func writeJSON(_ config: [String: Any], to link: URL) throws {
        // A symlinked settings file (a dotfiles repo) stays a link: write to what it points at.
        let url = link.resolvingSymlinksInPath()
        do {
            try writeJSONFile(config, to: url)
        } catch {
            throw Failure(message: "Couldn't update \(display(link)): \((error as NSError).localizedFailureReason ?? error.localizedDescription)")
        }
    }

    private static func writeJSONFile(_ config: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).ghostty-extreme-backup-\(AgentTools.timestamp())")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        var data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
#endif
