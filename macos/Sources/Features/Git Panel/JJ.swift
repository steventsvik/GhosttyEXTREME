#if os(macOS)
import Foundation

/// Jujutsu (jj), the version control system that keeps every operation undoable. Most jj
/// repositories keep a git repository beside `.jj` ("colocated"), so git still works in
/// them; GhosttyEXTREME reads jj for what git can't tell (the change you're on, its
/// bookmarks, the operation log) and shows jj's actions in the Git panel.
enum JJ {
    /// The jj executable, if installed.
    static var binary: String? { ToolPath.find("jj") }

    /// Whether `root` (a repository's top folder) is a jj repository.
    static func isRepo(_ root: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: root + "/.jj", isDirectory: &isDir) && isDir.boolValue
    }

    /// Runs jj synchronously. Call off the main thread.
    ///
    /// Any jj command first records the working copy's edits as an operation ("snapshot").
    /// Pass `snapshot: false` for reads that run on a timer, so polling never fills the
    /// operation log or races an agent's own jj commands.
    @discardableResult
    static func run(_ args: [String], in directory: String, snapshot: Bool = true) -> AgentTools.Result {
        guard let binary else { return AgentTools.Result(status: -1, output: "", error: "jj isn't installed") }
        // An editor would wait forever; every command here passes its message.
        return ToolPath.run(binary, ["--repository", directory, "--no-pager", "--color=never"]
                                + (snapshot ? [] : ["--ignore-working-copy"]) + args,
                            in: directory, environment: ["JJ_EDITOR": "true"])
    }

    // MARK: What the sidebar shows

    /// The working-copy change, for the sidebar: the nearest bookmark at or below it (what a
    /// pull request is named after), or the change's short ID.
    struct Status: Equatable {
        let changeID: String
        let bookmark: String?
        let conflict: Bool
        /// The working copy's change has no description yet.
        let undescribed: Bool

        var label: String { bookmark ?? changeID }
    }

    static func status(_ root: String) -> Status? {
        let template = #"change_id.shortest(8) ++ "\t" ++ if(conflict, "c", "") ++ "\t" ++ if(description, "", "u") ++ "\n""#
        let current = run(["log", "--no-graph", "-r", "@", "-T", template], in: root, snapshot: false)
        guard current.ok, let line = current.output.split(separator: "\n").first else { return nil }
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3 else { return nil }
        let bookmark = run(["log", "--no-graph", "-r", "heads(::@ & bookmarks())", "-n", "1",
                            "-T", #"local_bookmarks.map(|b| b.name()).join(" ") ++ "\n""#], in: root, snapshot: false)
            .output.split(separator: "\n").first?.split(separator: " ").first.map(String.init)
        return Status(changeID: f[0], bookmark: bookmark, conflict: f[1] == "c", undescribed: f[2] == "u")
    }

    /// Lines added and removed in the working-copy change since jj last recorded it.
    static func diffStats(_ root: String) -> (Int, Int) {
        let output = run(["diff", "--stat", "-r", "@"], in: root, snapshot: false).output
        let summary = output.split(separator: "\n").last.map(String.init) ?? ""
        func number(before word: String) -> Int {
            for part in summary.split(separator: ",") where part.contains(word) {
                return Int(part.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }) ?? 0
            }
            return 0
        }
        return (number(before: "insertion"), number(before: "deletion"))
    }

    /// The newest operation's ID; with `snapshot`, after recording the working copy's edits.
    static func currentOperation(_ root: String, snapshot: Bool = false) -> String? {
        let result = run(["op", "log", "--no-graph", "-n", "1", "-T", #"id.short(12) ++ "\n""#], in: root, snapshot: snapshot)
        let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.ok && !id.isEmpty ? id : nil
    }

    /// Operations after `operation`, newest first, leaving out working-copy snapshots: what
    /// someone actually ran with jj since then.
    static func operations(since operation: String, in root: String) -> [String] {
        let output = run(["op", "log", "--no-graph", "-n", "40", "-T", #"id.short(12) ++ "\t" ++ description.first_line() ++ "\n""#],
                         in: root, snapshot: false).output
        var found: [String] = []
        for line in output.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard f.count == 2 else { continue }
            if f[0] == operation { return found }
            if f[1] != "snapshot working copy" { found.append(shortenHashes(f[1])) }
        }
        // The starting operation is too far back to say.
        return found
    }

    /// "describe commit 034f6967387b4fd2f52ab09a377a4bd8f7a144b2" → "describe commit 034f6967387b".
    static func shortenHashes(_ text: String) -> String {
        text.replacingOccurrences(of: #"\b([0-9a-f]{12})[0-9a-f]{28,116}\b"#, with: "$1", options: .regularExpression)
    }
}
#endif
