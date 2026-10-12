#if os(macOS)
import Foundation

/// GitButler: several branches applied in one working folder at once, so agents can work
/// on separate branches side by side. Its CLI is `but`; while it manages a repository, git
/// sits on a `gitbutler/workspace` branch that merges every applied branch.
enum GitButler {
    static let workspaceBranch = "gitbutler/workspace"

    static var binary: String? { ToolPath.find("but") }

    struct Branch: Identifiable, Equatable {
        let name: String
        let commits: [String]
        /// GitButler's push state, e.g. "completelyUnpushed".
        let status: String
        var id: String { name }

        var statusText: String {
            if commits.isEmpty { return "nothing committed yet" }
            switch status {
            case "completelyUnpushed": return "not pushed"
            case "nothingToPush": return "pushed"
            case "unpushedCommits", "unpushedCommitsRequiringForce": return "commits to push"
            case "integrated": return "merged"
            default:
                // Other states, spelled out: "someNewState" → "some new state".
                return status.reduce("") { $0 + ($1.isUppercase ? " " + $1.lowercased() : String($1)) }
            }
        }
    }

    struct Stack: Identifiable, Equatable {
        let id: String
        /// Top of the stack first.
        let branches: [Branch]
        /// Uncommitted files assigned to this stack.
        let assigned: [String]
    }

    struct Status: Equatable {
        let unassigned: [String]
        let stacks: [Stack]
        /// Commits on the target branch (usually origin/main) not yet in the workspace.
        let behind: Int
    }

    static func status(_ root: String) -> Status? {
        guard let binary else { return nil }
        let result = ToolPath.run(binary, ["status", "--json"], in: root)
        guard result.ok, let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else { return nil }
        func paths(_ value: Any?) -> [String] { (value as? [[String: Any]] ?? []).compactMap { $0["filePath"] as? String } }
        let stacks = (json["stacks"] as? [[String: Any]] ?? []).map { stack in
            Stack(id: stack["cliId"] as? String ?? UUID().uuidString,
                  branches: (stack["branches"] as? [[String: Any]] ?? []).map { branch in
                      Branch(name: branch["name"] as? String ?? "?",
                             commits: (branch["commits"] as? [[String: Any]] ?? []).compactMap {
                                 ($0["message"] as? String)?.split(separator: "\n").first.map(String.init)
                             },
                             status: branch["branchStatus"] as? String ?? "")
                  },
                  assigned: paths(stack["assignedChanges"]))
        }
        let behind = (json["upstreamState"] as? [String: Any])?["behind"] as? Int ?? 0
        return Status(unassigned: paths(json["uncommittedChanges"]), stacks: stacks, behind: behind)
    }

    /// The branches the workspace merges, read from git alone (for the sidebar).
    static func appliedBranches(_ root: String) -> [String] {
        let parents = AgentTools.git(["log", "-1", "--format=%P", "HEAD"], in: root).output
            .split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var names: [String] = []
        for parent in Set(parents) where !parent.isEmpty {
            let refs = AgentTools.git(["for-each-ref", "--points-at", parent, "--format=%(refname:short)", "refs/heads"], in: root).output
            for name in refs.split(separator: "\n").map(String.init)
            where !name.hasPrefix("gitbutler/") && !names.contains(name) && !["main", "master", "trunk"].contains(name) {
                names.append(name)
            }
        }
        return names.sorted()
    }
}

/// Graphite: stacked pull requests. `gt` records each branch's parent; the Git panel shows
/// the stack you're in and runs Graphite's own commands for it.
enum Graphite {
    static var binary: String? { ToolPath.find("gt", "graphite") }

    struct Branch: Identifiable, Equatable {
        let name: String
        let parent: String?
        let isTrunk: Bool
        /// Its parent moved on; `gt restack` rebases it.
        let needsRestack: Bool
        var id: String { name }
    }

    /// Whether Graphite tracks this repository (`gt init` was run).
    static func isTracked(_ root: String) -> Bool {
        let common = AgentTools.git(["rev-parse", "--git-common-dir"], in: root).output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !common.isEmpty else { return false }
        let dir = common.hasPrefix("/") ? common : (root as NSString).appendingPathComponent(common)
        return FileManager.default.fileExists(atPath: dir + "/.graphite_repo_config")
    }

    /// Every branch Graphite tracks, by name.
    static func state(_ root: String) -> [String: Branch]? {
        guard let binary else { return nil }
        let result = ToolPath.run(binary, ["state"], in: root, environment: ["GRAPHITE_INTERACTIVE": "false"])
        guard result.ok, let start = result.output.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(result.output[start...].utf8)) as? [String: Any] else { return nil }
        var branches: [String: Branch] = [:]
        for (name, value) in json {
            let info = value as? [String: Any] ?? [:]
            let parent = ((info["parents"] as? [[String: Any]])?.first)?["ref"] as? String
            branches[name] = Branch(name: name, parent: parent, isTrunk: info["trunk"] as? Bool ?? false,
                                    needsRestack: info["needs_restack"] as? Bool ?? false)
        }
        return branches
    }

    /// The stack `current` is in, top first: the branches built on it (following the first
    /// child at each step), itself, then its parents down to trunk.
    static func stack(containing current: String, in branches: [String: Branch]) -> [Branch] {
        guard let here = branches[current] else { return [] }
        var below: [Branch] = []
        var seen: Set<String> = [current]
        var parent = here.parent
        while let name = parent, let branch = branches[name], seen.insert(name).inserted {
            below.append(branch)
            parent = branch.parent
        }
        var above: [Branch] = []
        var tip = current
        while let child = branches.values.filter({ $0.parent == tip }).sorted(by: { $0.name < $1.name }).first,
              seen.insert(child.name).inserted {
            above.insert(child, at: 0)
            tip = child.name
        }
        return above + [here] + below
    }
}
#endif
