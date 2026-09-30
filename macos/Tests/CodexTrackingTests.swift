import Foundation
import Testing
@testable import Ghostty

struct CodexTrackingTests {
    @Test @MainActor func liveFeedFollowsOnlyLinkedChildrenAndSkipsInheritedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ records: [[String: Any]]) throws -> String {
            let data = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }.reduce(Data(), +)
            let path = directory.appendingPathComponent(name)
            try data.write(to: path)
            return path.path
        }
        let parent = "fixture-\(UUID().uuidString)"
        let root = try write("root.jsonl", [
            ["type": "session_meta", "payload": ["id": parent, "cwd": directory.path]],
            ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["text": "Inspect files"]]]],
        ])
        _ = try write("child.jsonl", [
            ["type": "session_meta", "payload": ["id": "fixture-child", "parent_thread_id": parent,
                "agent_path": "/root/reviewer", "subagent_history_start_ordinal": 41]],
            ["ordinal": 2, "type": "response_item", "payload": ["type": "function_call", "name": "exec_command",
                "call_id": "inherited", "arguments": "{\"cmd\":\"cat inherited.ts\"}"]],
            ["ordinal": 42, "type": "response_item", "payload": ["type": "function_call", "name": "exec_command",
                "call_id": "child-read", "arguments": "{\"cmd\":\"cat child.ts\"}"]],
        ])
        _ = try write("unrelated.jsonl", [
            ["type": "session_meta", "payload": ["id": "other-child", "parent_thread_id": "different-parent"]],
            ["type": "response_item", "payload": ["type": "function_call", "name": "exec_command",
                "call_id": "unrelated", "arguments": "{\"cmd\":\"cat unrelated.ts\"}"]],
        ])
        let feed = AgentFeed()
        defer { feed.stop() }
        var received: [[String: Any]] = []
        feed.onItems = { items, reset in
            if reset { received.removeAll() }
            received += items
        }
        feed.follow(path: root, kind: .codex)
        for _ in 0..<50 {
            if received.contains(where: { $0["command"] as? String == "cat child.ts" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let child = received.first { $0["command"] as? String == "cat child.ts" }
        #expect(child != nil)
        #expect((child?["sub"] as? String)?.hasPrefix("reviewer") == true)
        #expect(!received.contains { $0["command"] as? String == "cat inherited.ts" })
        #expect(!received.contains { $0["command"] as? String == "cat unrelated.ts" })
    }

    @Test func nativePatchCompletionDeduplicatesRelativeHookPaths() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("src/a.ts").path
        let feed = CodexFeed()
        let calls = feed.hookItems(["event": "pre_tool_use", "payload": ["tool_use_id": "patch", "tool_name": "apply_patch",
            "cwd": directory.path, "tool_input": ["command": "*** Begin Patch\n*** Add File: src/a.ts\n+hello\n*** End Patch"]]], scope: "parent")
        #expect(calls.first?["path"] as? String == path)
        try "hello\n".write(toFile: path, atomically: true, encoding: .utf8)
        let completed = feed.items(["type": "event_msg", "payload": ["type": "item_completed", "item": ["type": "FileChange",
            "id": "patch", "status": "Completed", "changes": [path: ["type": "add", "content": "hello"]]]]], scope: "parent", hooks: true)
        #expect(completed.count == 1)
        #expect(completed.first?["kind"] as? String == "result")
    }

    @Test func nativeCodeModeCompletionsIncludeEveryToolAndDeduplicateHooks() {
        let feed = CodexFeed()
        _ = feed.hookItems(["event": "pre_tool_use", "payload": ["tool_use_id": "exec-1", "tool_name": "Bash",
            "tool_input": ["command": "cat src/a.ts"]]], scope: "parent")
        let first = feed.items(["type": "event_msg", "payload": ["type": "item_completed", "item": [
            "type": "CommandExecution", "id": "exec-1", "command": "cat src/a.ts", "exit_code": 0]]], scope: "parent", hooks: true)
        #expect(first.count == 1)
        #expect(first.first?["kind"] as? String == "result")
        let second = feed.items(["type": "event_msg", "payload": ["type": "item_completed", "item": [
            "type": "CommandExecution", "id": "exec-2", "command": "npm test", "exit_code": 2]]], scope: "parent", hooks: false)
        #expect(second.count == 2)
        #expect(second.last?["error"] as? Bool == true)
    }
    @Test func nestedToolsAndResultsAreNotDuplicated() {
        let feed = CodexFeed()
        let call: [String: Any] = ["event": "pre_tool_use", "payload": [
            "tool_use_id": "nested-1", "tool_name": "Bash", "tool_input": ["command": "cat src/app.ts"]]]
        let items = feed.hookItems(call, scope: "parent")
        #expect(items.count == 1)
        #expect(items.first?["command"] as? String == "cat src/app.ts")
        #expect(feed.hookItems(call, scope: "parent").isEmpty)
        #expect(feed.hookItems(call, scope: "child").count == 1)
        let wrapper: [String: Any] = ["type": "response_item", "payload": [
            "type": "custom_tool_call", "name": "exec", "call_id": "wrapper", "input": "await tools.exec_command({cmd: 'cat src/app.ts'})"]]
        #expect(feed.items(wrapper, scope: "parent", hooks: true).isEmpty)
    }

    @Test func multiFilePatchAndFailure() {
        let feed = CodexFeed()
        let patch = "*** Begin Patch\n*** Update File: src/a.ts\n@@\n-old\n+new\n*** Add File: src/b.ts\n+hello\n*** Delete File: src/c.ts\n*** End Patch"
        let tools = feed.tools(id: "patch", name: "apply_patch", input: ["command": patch], time: "")
        #expect(tools.count == 3)
        #expect(tools.compactMap { $0["path"] as? String } == ["src/a.ts", "src/b.ts", "src/c.ts"])
        let results = feed.results(id: "patch", output: ["exit_code": 1, "output": "Patch failed"], time: "")
        #expect(results.count == 3)
        #expect(results.allSatisfy { $0["error"] as? Bool == true })
        #expect(results.compactMap { $0["id"] as? String } == tools.compactMap { $0["id"] as? String })
    }

    @Test func codeModeHooksIncludeEveryNestedCommand() {
        let feed = CodexFeed()
        let items = ["cat src/a.ts", "sed -n '1,20p' src/b.ts", "npm test"].enumerated().flatMap { index, command in
            feed.hookItems(["event": "pre_tool_use", "payload": ["tool_use_id": "call-\(index)", "tool_name": "Bash",
                                                                  "tool_input": ["command": command]]], scope: "parent")
        }
        #expect(items.count == 3)
        #expect(items.last?["command"] as? String == "npm test")
    }

    @Test func childMetadataIncludesIdentityAndInheritedHistoryBoundary() {
        let child = CodexTracking.metadata([
            "parent_thread_id": "parent", "subagent_history_start_ordinal": 41,
            "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent", "agent_path": "/root/reviewer"]]]],
            path: "/tmp/child.jsonl", id: "child")
        #expect(child.parent == "parent")
        #expect(child.label == "reviewer")
        #expect(child.historyStart == 41)
        #expect(CodexTracking.hookPath("../../other") == nil)
    }

    @Test func structuredAndTextualFailures() {
        let feed = CodexFeed()
        let outputs: [Any] = ["Process exited with code 2", "Exit code: 1", "{\"metadata\":{\"exit_code\":127},\"output\":\"missing\"}", ["isError": true]]
        for output in outputs {
            #expect(feed.results(id: "run", output: output, time: "").first?["error"] as? Bool == true)
        }
        #expect(feed.results(id: "run", output: "Process exited with code 0", time: "").first?["error"] as? Bool == false)
    }

    @Test func reconstructsCallWhenOnlyCompletionIsAvailable() {
        let feed = CodexFeed()
        let items = feed.hookItems(["event": "tool_complete", "payload": ["tool_use_id": "run", "tool_name": "Bash",
            "tool_input": ["command": "npm test"], "tool_response": "Exit code: 1"]], scope: "parent")
        #expect(items.count == 2)
        #expect(items.first?["kind"] as? String == "tool")
        #expect(items.last?["error"] as? Bool == true)
    }
}
