#if os(macOS)
import Foundation
import Combine

/// Git branch and uncommitted diff size for a working directory.
struct VerticalTabsGitInfo: Equatable {
    let branch: String
    let added: Int
    let removed: Int
}

/// Looks up git info for the directories shown in the sidebar. Branch names are read
/// straight from `.git/HEAD` (cheap); diff stats shell out to `git` in the background
/// and are cached per repository so many tabs in one repo cost a single call.
final class VerticalTabsGit: ObservableObject {
    static let shared = VerticalTabsGit()

    /// Keyed by repository root.
    @Published private(set) var info: [String: VerticalTabsGitInfo] = [:]

    private var lastFetch: [String: Date] = [:]
    private var inFlight: Set<String> = []
    private let minInterval: TimeInterval = 4
    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-custom.git", qos: .utility)

    /// Returns cached info for the repo containing `pwd` and schedules a refresh if stale.
    func info(for pwd: String?) -> VerticalTabsGitInfo? {
        guard let pwd, let root = Self.repoRoot(containing: pwd) else { return nil }
        refreshIfStale(root: root)
        return info[root.path]
    }

    private func refreshIfStale(root: RepoRoot) {
        let key = root.path
        if inFlight.contains(key) { return }
        if let last = lastFetch[key], Date().timeIntervalSince(last) < minInterval { return }
        inFlight.insert(key)
        lastFetch[key] = Date()

        queue.async { [weak self] in
            let branch = Self.readBranch(gitDir: root.gitDir) ?? "HEAD"
            let (added, removed) = Self.diffStats(repo: key)
            let result = VerticalTabsGitInfo(branch: branch, added: added, removed: removed)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(key)
                if self.info[key] != result { self.info[key] = result }
            }
        }
    }

    struct RepoRoot {
        let path: String
        let gitDir: String
    }

    /// Walks up from `path` to find the repository. Handles worktrees and submodules,
    /// where `.git` is a file pointing at the real git directory.
    static func repoRoot(containing path: String) -> RepoRoot? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path).standardizedFileURL
        while true {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return RepoRoot(path: dir.path, gitDir: dotGit.path)
                }
                if let contents = try? String(contentsOf: dotGit, encoding: .utf8),
                   let line = contents.split(separator: "\n").first,
                   line.hasPrefix("gitdir: ") {
                    let target = String(line.dropFirst("gitdir: ".count))
                    let resolved = URL(fileURLWithPath: target, relativeTo: dir).standardizedFileURL
                    return RepoRoot(path: dir.path, gitDir: resolved.path)
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    private static func readBranch(gitDir: String) -> String? {
        let head = URL(fileURLWithPath: gitDir).appendingPathComponent("HEAD")
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        // Detached HEAD: show the short hash.
        return String(trimmed.prefix(7))
    }

    /// Lines added/removed across staged and unstaged changes, via `git diff --shortstat HEAD`.
    private static func diffStats(repo: String) -> (Int, Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo, "--no-optional-locks", "diff", "--shortstat", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (0, 0)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return (0, 0) }
        return (number(before: "insertion", in: output), number(before: "deletion", in: output))
    }

    /// Parses e.g. "3 files changed, 10 insertions(+), 2 deletions(-)".
    private static func number(before word: String, in text: String) -> Int {
        for part in text.split(separator: ",") where part.contains(word) {
            let digits = part.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        return 0
    }
}
#endif
