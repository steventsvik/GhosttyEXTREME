#if os(macOS)
import Foundation

/// Normalizes Codex rollouts and nested tool hooks to the existing editor timeline.
/// No JavaScript is evaluated: tools in code mode come from the actual hook events.
final class CodexFeed {
    private var patchIDs: [String: [String]] = [:]
    private var seen: Set<String> = []

    func reset() {
        patchIDs.removeAll()
        seen.removeAll()
    }

    private func clip(_ value: String, _ limit: Int = 4000) -> String {
        value.count > limit ? String(value.prefix(limit)) + "…" : value
    }

    // File creation must not change an action's identity. NSString.standardizingPath
    // can resolve /private/tmp differently once a newly added file exists.
    private static func normalizedPath(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
        var components: [String] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !absolute { components.append("..") }
            } else { components.append(String(part)) }
        }
        return (absolute ? "/" : "") + components.joined(separator: "/")
    }

    private func unique(_ items: [[String: Any]], scope: String) -> [[String: Any]] {
        items.filter { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return true }
            let key = scope + ":" + (item["kind"] as? String ?? "") + ":" + id
            return seen.insert(key).inserted
        }
    }

    func hookItems(_ record: [String: Any], scope: String) -> [[String: Any]] {
        guard let payload = record["payload"] as? [String: Any] else { return [] }
        let time = (record["timestamp"] as? Double).map {
            ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0))
        } ?? ""
        let id = payload["tool_use_id"] as? String ?? ""
        var input = payload["tool_input"] as? [String: Any] ?? [:]
        if input["workdir"] == nil, input["cwd"] == nil { input["cwd"] = payload["cwd"] }
        switch record["event"] as? String {
        case "pre_tool_use":
            return unique(tools(id: id, name: payload["tool_name"] as? String ?? "Tool",
                                input: input, time: time), scope: scope)
        case "tool_complete":
            // If the editor starts after PreToolUse, reconstruct the call before its result.
            let calls = unique(tools(id: id, name: payload["tool_name"] as? String ?? "Tool",
                                     input: input, time: time), scope: scope)
            return calls + unique(results(id: id, output: payload["tool_response"], time: time), scope: scope)
        default: return []
        }
    }

    func items(_ record: [String: Any], scope: String, hooks: Bool) -> [[String: Any]] {
        if record["type"] as? String == "event_msg",
           let payload = record["payload"] as? [String: Any], payload["type"] as? String == "item_completed",
           let item = payload["item"] as? [String: Any] {
            return completed(item, scope: scope, time: record["timestamp"] as? String ?? "")
        }
        guard record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any] else { return [] }
        let time = record["timestamp"] as? String ?? ""
        let id = payload["call_id"] as? String ?? ""
        switch payload["type"] as? String {
        case "agent_message":
            let text = (payload["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            guard !text.isEmpty else { return [] }
            return [["kind": "message", "text": clip(text), "time": time]]
        case "message":
            let text = (payload["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            guard !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("# AGENTS.md") else { return [] }
            switch payload["role"] as? String {
            case "user": return [["kind": "prompt", "text": clip(text), "time": time]]
            case "assistant": return [["kind": "message", "text": clip(text), "time": time]]
            default: return []
            }
        case "reasoning":
            let summary = (payload["summary"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            return [["kind": "thinking", "text": clip(summary), "time": time]]
        case "function_call", "custom_tool_call", "local_shell_call":
            let name = payload["name"] as? String ?? "local_shell"
            // The nested calls have their own hook ids; a wrapper is not an extra command.
            if hooks && ["exec", "functions.exec"].contains(name) { return [] }
            var input = payload["action"] as? [String: Any] ?? [:]
            if let args = payload["arguments"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(args.utf8)) as? [String: Any] { input = parsed }
            if let patch = payload["input"] as? String, name.hasSuffix("apply_patch") { input["command"] = patch }
            return unique(tools(id: id, name: name, input: input, time: time), scope: scope)
        case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
            if hooks && !seen.contains(scope + ":tool:" + id) && patchIDs[id] == nil { return [] }
            return unique(results(id: id, output: payload["output"], time: time), scope: scope)
        default: return []
        }
    }

    func tools(id: String, name: String, input: [String: Any], time: String) -> [[String: Any]] {
        let name = name.components(separatedBy: ".").last ?? name
        let action: String
        switch name {
        case "Read", "read_file", "NotebookRead": action = "read"
        case "apply_patch", "Edit", "Write", "MultiEdit": action = "edit"
        case "Bash", "shell", "local_shell", "exec_command", "write_stdin": action = "run"
        case "Grep", "Glob", "LS", "ToolSearch": action = "search"
        case "web", "web_search", "WebSearch", "WebFetch", "web__run": action = "web"
        case "spawn_agent", "send_message", "followup_task", "wait_agent", "Task", "Agent": action = "agent"
        case "update_plan", "TodoWrite": action = "todo"
        case "request_user_input", "request_user_input_async": action = "other"
        default: action = "other"
        }
        var item: [String: Any] = ["kind": "tool", "id": id, "tool": name, "action": action, "time": time]
        if let path = input["file_path"] as? String ?? input["path"] as? String { item["path"] = path }
        let command = input["command"] as? String ?? input["cmd"] as? String ??
            (input["command"] as? [String])?.joined(separator: " ")
        if let command { item["command"] = clip(command, 4000) }
        if let cwd = input["workdir"] as? String ?? input["cwd"] as? String { item["cwd"] = cwd }
        for key in ["offset", "limit", "pattern", "description", "old_string", "new_string"] {
            if let value = input[key] { item[key == "old_string" ? "old" : key == "new_string" ? "new" : key] = value }
        }
        if let text = input["message"] as? String ?? input["prompt"] as? String ?? input["url"] as? String ?? input["query"] as? String {
            item["query"] = clip(text, 300)
        }
        if let plan = input["plan"] as? [[String: Any]] {
            item["todos"] = plan.map { ["text": $0["step"] ?? "", "status": $0["status"] ?? ""] }
        }
        if name == "apply_patch", let patch = command {
            let files = Self.patchFiles(patch)
            if !files.isEmpty {
                let base = input["workdir"] as? String ?? input["cwd"] as? String
                let paths = files.map { file in
                    Self.normalizedPath(file.path.hasPrefix("/") ? file.path :
                        base.map { ($0 as NSString).appendingPathComponent(file.path) } ?? file.path)
                }
                let ids = paths.map { id + ":file:" + $0 }
                patchIDs[id] = ids
                return files.enumerated().map { index, file in
                    var edit = item
                    edit["id"] = ids[index]
                    edit["path"] = paths[index]
                    edit["patch"] = clip(file.patch, 8000)
                    edit.removeValue(forKey: "command")
                    return edit
                }
            }
        }
        return [item]
    }

    /// Native completed items preserve nested code-mode actions, even for older sessions
    /// recorded before hooks were installed. Their ids match Codex's tool hook ids.
    private func completed(_ item: [String: Any], scope: String, time: String) -> [[String: Any]] {
        let id = item["id"] as? String ?? ""
        switch item["type"] as? String {
        case "CommandExecution":
            let calls = unique(tools(id: id, name: "exec_command", input: [
                "command": item["command"] ?? "", "cwd": item["cwd"] ?? ""], time: time), scope: scope)
            return calls + unique(results(id: id, output: ["output": item["aggregated_output"] ?? item["formatted_output"] ?? "",
                "exit_code": item["exit_code"] ?? 0], time: time), scope: scope)
        case "FileChange":
            guard let changes = item["changes"] as? [String: [String: Any]] else { return [] }
            let paths = changes.keys.sorted()
            let ids = paths.map { id + ":file:" + Self.normalizedPath($0) }
            patchIDs[id] = ids
            let calls = paths.enumerated().map { index, path -> [String: Any] in
                let change = changes[path] ?? [:]
                var tool: [String: Any] = ["kind": "tool", "id": ids[index], "tool": "apply_patch", "action": "edit", "path": path, "time": time]
                if let diff = change["unified_diff"] as? String { tool["patch"] = clip(diff, 8000) }
                if let content = change["content"] as? String { tool["new"] = clip(content) }
                return tool
            }
            return unique(calls, scope: scope) + unique(results(id: id, output: [
                "output": item["stdout"] ?? "", "is_error": (item["status"] as? String)?.lowercased() == "failed"], time: time), scope: scope)
        case "McpToolCall":
            var input = item["arguments"] as? [String: Any] ?? [:]
            if let raw = item["arguments"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] { input = parsed }
            let calls = unique(tools(id: id, name: item["tool"] as? String ?? "MCP", input: input, time: time), scope: scope)
            return calls + unique(results(id: id, output: item["result"], time: time), scope: scope)
        default: return []
        }
    }

    static func patchFiles(_ patch: String) -> [(path: String, patch: String)] {
        var files: [(path: String, patch: String)] = []
        for line in patch.components(separatedBy: "\n") {
            if let marker = ["*** Update File: ", "*** Add File: ", "*** Delete File: "].first(where: { line.hasPrefix($0) }) {
                files.append((String(line.dropFirst(marker.count)), line + "\n"))
            } else if !files.isEmpty { files[files.count - 1].patch += line + "\n" }
        }
        return files
    }

    func results(id: String, output: Any?, time: String) -> [[String: Any]] {
        let data: [String: Any]?
        let text: String
        if let raw = output as? String {
            text = raw
            data = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        } else {
            data = output as? [String: Any]
            if let output { text = (try? JSONSerialization.data(withJSONObject: output, options: [.fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "" } else { text = "" }
        }
        let metadata = data?["metadata"] as? [String: Any]
        let code = data?["exit_code"] as? Int ?? metadata?["exit_code"] as? Int
        let textualFailure = text.range(of: #"(?:Process exited with code|Exit code:)\s*[1-9][0-9]*"#,
                                        options: .regularExpression) != nil
        let error = data?["isError"] as? Bool == true || data?["is_error"] as? Bool == true ||
            (code != nil && code != 0) || textualFailure
        let display = data?["output"] as? String ?? data?["stdout"] as? String ?? text
        return (patchIDs[id] ?? [id]).map { resultID in
            ["kind": "result", "id": resultID, "error": error, "text": clip(display, 1500), "time": time]
        }
    }
}
#endif
