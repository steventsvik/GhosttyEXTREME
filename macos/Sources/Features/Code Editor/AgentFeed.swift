#if os(macOS)
import Foundation

/// Tails an agent's session transcript (JSONL) and turns new records into timeline items
/// for the editor's Agent panel: prompts, thinking, messages, tool calls and results.
///
/// Only bytes appended since the last read are processed, on a background queue, and
/// only while the editor panel is open.
final class AgentFeed {
    typealias Item = [String: Any]

    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-extreme.agent-feed", qos: .utility)
    private var kind: VerticalTabAgentKind = .unknown
    private(set) var path: String?

    /// The session transcript, plus one per sub-agent (Claude Code runs sub-agents with
    /// their own transcripts in `<session>/subagents/`; they often do the actual reading).
    private var main: Tail?
    private var subagents: [String: Tail] = [:]
    private var subagentDir: String?
    private var scanTimer: DispatchSourceTimer?

    /// Called on the main queue with (items, isReset).
    var onItems: (([Item], Bool) -> Void)?

    /// How far back to look when starting to follow a session: enough to reach the start of
    /// the current turn, so an editor opened mid-prompt shows everything the agent did.
    private let backlog: UInt64 = 8 * 1024 * 1024
    /// Most items sent when starting to follow.
    private let maxBacklogItems = 500
    private let maxText = 4000

    func follow(path: String, kind: VerticalTabAgentKind) {
        guard path != self.path else { return }
        stop()
        self.path = path
        self.kind = kind
        queue.async { [self] in
            guard let tail = Tail(path: path, startFromEnd: backlog) else { return }
            main = tail
            let items = Self.fromPreviousTurn(tail.readNew().flatMap { self.items(from: $0, subagent: nil) },
                                              limit: maxBacklogItems)
            DispatchQueue.main.async { self.onItems?(items, true) }
            tail.watch(on: queue) { [weak self] in self?.drain(tail, subagent: nil) }

            // Sub-agents that already exist are followed from now on; new ones from the start.
            subagentDir = (path as NSString).deletingPathExtension + "/subagents"
            scanSubagents(existingFromEnd: true)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.scanSubagents(existingFromEnd: false) }
            timer.resume()
            scanTimer = timer
        }
    }

    func stop() {
        path = nil
        queue.async { [self] in
            scanTimer?.cancel()
            scanTimer = nil
            main?.close()
            main = nil
            subagents.values.forEach { $0.close() }
            subagents.removeAll()
            subagentDir = nil
        }
    }

    /// The current turn and the one before it (from the second-to-last prompt), capped.
    private static func fromPreviousTurn(_ items: [Item], limit: Int) -> [Item] {
        let prompts = items.indices.filter { items[$0]["kind"] as? String == "prompt" }
        let start = prompts.count >= 2 ? prompts[prompts.count - 2] : 0
        return Array(items[start...].suffix(limit))
    }

    private func scanSubagents(existingFromEnd: Bool) {
        guard let dir = subagentDir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for name in names where name.hasSuffix(".jsonl") && subagents[name] == nil {
            let file = dir + "/" + name
            // Sub-agents already running when following starts show their recent work too.
            let modified = (try? FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date) ?? .distantPast
            let recent = Date().timeIntervalSince(modified) < 600
            guard let tail = Tail(path: file, startFromEnd: existingFromEnd ? (recent ? 512 * 1024 : 0) : nil) else { continue }
            let label = Self.subagentLabel(meta: (file as NSString).deletingPathExtension + ".meta.json")
            subagents[name] = tail
            drain(tail, subagent: label)
            tail.watch(on: queue) { [weak self] in self?.drain(tail, subagent: label) }
        }
    }

    private func drain(_ tail: Tail, subagent: String?) {
        let items = tail.readNew().flatMap { self.items(from: $0, subagent: subagent) }
        guard !items.isEmpty else { return }
        DispatchQueue.main.async { self.onItems?(items, false) }
    }

    private static func subagentLabel(meta: String) -> String {
        guard let data = FileManager.default.contents(atPath: meta),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let description = json["description"] as? String, !description.isEmpty else { return "Sub-agent" }
        return description
    }

    private func items(from record: [String: Any], subagent: String?) -> [Item] {
        var items = kind == .codex ? codexItems(record) : claudeItems(record)
        if let subagent {
            // A sub-agent's first message is its instructions, not the user's prompt.
            items = items.filter { $0["kind"] as? String != "prompt" }
            for index in items.indices { items[index]["sub"] = subagent }
        }
        return items
    }

    /// Follows one JSONL file: reads only appended bytes, keeps partial lines for later.
    private final class Tail {
        private let handle: FileHandle
        private var offset: UInt64
        private var partial = Data()
        private var skipFirstLine: Bool
        private var source: DispatchSourceFileSystemObject?

        /// `startFromEnd`: nil = whole file, 0 = only new data, n = the last n bytes.
        init?(path: String, startFromEnd: UInt64?) {
            guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
            self.handle = handle
            let size = (try? handle.seekToEnd()) ?? 0
            if let n = startFromEnd { offset = size > n ? size - n : 0 } else { offset = 0 }
            skipFirstLine = offset > 0 && startFromEnd != 0
        }

        func watch(on queue: DispatchQueue, _ handler: @escaping () -> Void) {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: handle.fileDescriptor, eventMask: [.extend, .write], queue: queue)
            source.setEventHandler(handler: handler)
            source.resume()
            self.source = source
        }

        func readNew() -> [[String: Any]] {
            try? handle.seek(toOffset: offset)
            let data = handle.readDataToEndOfFile()
            offset += UInt64(data.count)
            var buffer = partial + data
            if skipFirstLine, let newline = buffer.firstIndex(of: 0x0A) {
                buffer = buffer[(newline + 1)...]
                skipFirstLine = false
            }
            guard let lastNewline = buffer.lastIndex(of: 0x0A) else {
                partial = Data(buffer)
                return []
            }
            partial = Data(buffer[(lastNewline + 1)...])
            return buffer[..<lastNewline].split(separator: 0x0A).compactMap {
                try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
            }
        }

        func close() {
            source?.cancel()
            try? handle.close()
        }
    }

    private func clip(_ text: String?, _ limit: Int? = nil) -> String {
        guard let text else { return "" }
        let limit = limit ?? maxText
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    // MARK: Claude Code

    private func claudeItems(_ record: [String: Any]) -> [Item] {
        guard let type = record["type"] as? String, let message = record["message"] as? [String: Any] else { return [] }
        let time = record["timestamp"] as? String ?? ""
        if type == "user" {
            if let text = message["content"] as? String {
                // Local command output and system reminders aren't prompts.
                return text.hasPrefix("<") ? [] : [["kind": "prompt", "text": clip(text), "time": time]]
            }
            var items: [Item] = []
            for block in message["content"] as? [[String: Any]] ?? [] {
                switch block["type"] as? String {
                case "tool_result":
                    items.append([
                        "kind": "result",
                        "id": block["tool_use_id"] as? String ?? "",
                        "error": block["is_error"] as? Bool ?? false,
                        "text": clip(resultText(block["content"]), 1500),
                    ])
                case "text":
                    let text = block["text"] as? String ?? ""
                    if !text.hasPrefix("<") { items.append(["kind": "prompt", "text": clip(text), "time": time]) }
                default: break
                }
            }
            return items
        }
        guard type == "assistant" else { return [] }
        var items: [Item] = []
        for block in message["content"] as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "thinking":
                // Thinking can be hidden; still show that the agent was thinking.
                items.append(["kind": "thinking", "text": clip(block["thinking"] as? String), "time": time])
            case "redacted_thinking":
                items.append(["kind": "thinking", "text": "", "time": time])
            case "text":
                let text = block["text"] as? String ?? ""
                if !text.isEmpty { items.append(["kind": "message", "text": clip(text), "time": time]) }
            case "tool_use":
                items.append(toolItem(
                    id: block["id"] as? String ?? "",
                    name: block["name"] as? String ?? "Tool",
                    input: block["input"] as? [String: Any] ?? [:],
                    time: time))
            default: break
            }
        }
        return items
    }

    private func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    /// Normalizes a tool call: which kind of action it is and its most useful details.
    private func toolItem(id: String, name: String, input: [String: Any], time: String) -> Item {
        var item: Item = ["kind": "tool", "id": id, "tool": name, "time": time]
        item["action"] = Self.action(for: name)
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? input["path"] as? String {
            item["path"] = path
        }
        if let command = input["command"] as? String { item["command"] = clip(command, 600) }
        // Where a read looks: Read's 1-based start line and line count.
        if let offset = input["offset"] as? Int { item["offset"] = offset }
        if let limit = input["limit"] as? Int { item["limit"] = limit }
        // Codex runs commands in a working directory; relative paths resolve against it.
        if let workdir = input["workdir"] as? String ?? input["cwd"] as? String { item["cwd"] = workdir }
        if let description = input["description"] as? String { item["description"] = clip(description, 200) }
        if let pattern = input["pattern"] as? String { item["pattern"] = clip(pattern, 200) }
        if let query = input["query"] as? String ?? input["url"] as? String ?? input["prompt"] as? String {
            item["query"] = clip(query, 300)
        }
        if let old = input["old_string"] as? String { item["old"] = clip(old, 2500) }
        if let new = input["new_string"] as? String { item["new"] = clip(new, 2500) }
        if let content = input["content"] as? String { item["new"] = clip(content, 2500) }
        if let edits = input["edits"] as? [[String: Any]], !edits.isEmpty {
            item["old"] = clip(edits.compactMap { $0["old_string"] as? String }.joined(separator: "\n⋯\n"), 2500)
            item["new"] = clip(edits.compactMap { $0["new_string"] as? String }.joined(separator: "\n⋯\n"), 2500)
        }
        if let todos = input["todos"] as? [[String: Any]] {
            item["todos"] = todos.prefix(12).map { ["text": $0["content"] ?? "", "status": $0["status"] ?? ""] }
        }
        return item
    }

    static func action(for name: String) -> String {
        switch name {
        case "Read", "NotebookRead": return "read"
        case "Edit", "MultiEdit", "NotebookEdit", "apply_patch": return "edit"
        case "Write": return "write"
        case "Bash", "BashOutput", "KillShell", "shell", "exec_command", "local_shell": return "run"
        case "Grep", "Glob", "LS", "ToolSearch": return "search"
        case "WebFetch", "WebSearch", "web_search": return "web"
        case "Task", "Agent": return "agent"
        case "TodoWrite", "update_plan": return "todo"
        default: return "other"
        }
    }

    // MARK: Codex

    /// A string argument in a code-mode script, e.g. `"cmd":"rg -n foo"` (JSON-escaped).
    static func codexScriptString(_ script: String, key: String) -> String? {
        guard let range = script.range(of: "\"\(key)\":\"") else { return nil }
        var value = ""
        var escaped = false
        for char in script[range.upperBound...] {
            if escaped { value.append(char == "n" ? "\n" : char == "t" ? "\t" : char); escaped = false; continue }
            if char == "\\" { escaped = true; continue }
            if char == "\"" { return value }
            value.append(char)
        }
        return nil
    }

    static func codexScriptCommand(_ script: String) -> String? {
        codexScriptString(script, key: "cmd") ?? codexScriptString(script, key: "command")
    }

    /// The patch text a code-mode script passes to `apply_patch`, if any.
    static func codexScriptPatch(_ script: String) -> String? {
        guard let begin = script.range(of: "*** Begin Patch"),
              let end = script.range(of: "*** End Patch", range: begin.upperBound..<script.endIndex) else { return nil }
        return String(script[begin.lowerBound..<end.upperBound])
            .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
    }

    static func patchPath(_ patch: String) -> String? {
        patch.split(separator: "\n").first { $0.hasPrefix("*** Update File: ") || $0.hasPrefix("*** Add File: ") }
            .map { String($0.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces) }
    }

    private func codexItems(_ record: [String: Any]) -> [Item] {
        guard record["type"] as? String == "response_item", let payload = record["payload"] as? [String: Any] else { return [] }
        let time = record["timestamp"] as? String ?? ""
        switch payload["type"] as? String {
        case "message":
            let text = (payload["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            guard !text.isEmpty, !text.hasPrefix("<") else { return [] }
            let role = payload["role"] as? String
            if role == "user" { return [["kind": "prompt", "text": clip(text), "time": time]] }
            if role == "assistant" { return [["kind": "message", "text": clip(text), "time": time]] }
            return []
        case "reasoning":
            let summary = (payload["summary"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            return [["kind": "thinking", "text": clip(summary), "time": time]]
        case "function_call", "custom_tool_call", "local_shell_call":
            let name = payload["name"] as? String ?? "shell"
            var input: [String: Any] = [:]
            if let args = payload["arguments"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(args.utf8)) as? [String: Any] {
                input = parsed
            }
            if let cmd = input["cmd"] as? String { input["command"] = cmd }
            if let parts = input["command"] as? [String] { input["command"] = parts.joined(separator: " ") }
            let script = payload["input"] as? String ?? ""
            if name == "exec" {
                // Code mode: the call is a script; show the first command or patch it runs.
                if let patch = Self.codexScriptPatch(script) {
                    var item = toolItem(id: payload["call_id"] as? String ?? "", name: "apply_patch", input: [:], time: time)
                    item["patch"] = clip(patch, 4000)
                    item["path"] = Self.patchPath(patch)
                    return [item]
                }
                if let command = Self.codexScriptCommand(script) { input["command"] = command }
                if let workdir = Self.codexScriptString(script, key: "workdir") { input["workdir"] = workdir }
                return [toolItem(id: payload["call_id"] as? String ?? "", name: "exec_command", input: input, time: time)]
            }
            var item = toolItem(id: payload["call_id"] as? String ?? "", name: name, input: input, time: time)
            if name == "apply_patch", let patch = payload["input"] as? String {
                item["patch"] = clip(patch, 4000)
                if let file = patch.split(separator: "\n").first(where: { $0.hasPrefix("*** Update File: ") || $0.hasPrefix("*** Add File: ") }) {
                    item["path"] = String(file.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                }
            }
            return [item]
        case "function_call_output", "custom_tool_call_output":
            let output = payload["output"] as? String ?? ""
            return [["kind": "result", "id": payload["call_id"] as? String ?? "", "error": false, "text": clip(output, 1500)]]
        default:
            return []
        }
    }
}
#endif
