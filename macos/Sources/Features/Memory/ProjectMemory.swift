#if os(macOS)
import Foundation

/// What the agents remember about a project, read from where each keeps it:
/// - Claude Code's notes: `~/.claude/projects/<folder>/memory/*.md`, one fact per file with a
///   name/description/type header, listed in `MEMORY.md`.
/// - Codex's memories: task groups in `~/.codex/memories/MEMORY.md`, each saying which folder
///   it applies to. Codex rewrites the file itself, so these are read-only here.
/// - Instruction files the agents load every session: `CLAUDE.md`, `CLAUDE.local.md`,
///   `.claude/CLAUDE.md` and `AGENTS.md` in the project, and the global ones.
enum ProjectMemory {
    struct Note: Identifiable, Hashable {
        enum Source: String, CaseIterable {
            case claude
            case codex
            case instructions

            var title: String {
                switch self {
                case .claude: return "Claude Code remembers"
                case .codex: return "Codex remembers"
                case .instructions: return "Instruction files"
                }
            }
        }

        let source: Source
        let path: String
        /// Codex's task group heading, which identifies it inside the shared file.
        let anchor: String?
        let title: String
        let summary: String
        /// Claude's note type (user, feedback, project, reference), or the file's role.
        let kind: String
        /// The text without Claude's header.
        let body: String
        /// The whole file, header included (what gets edited).
        let raw: String
        let modified: Date?

        var id: String { path + "#" + (anchor ?? "") }
        var editable: Bool { source != .codex }
        var fileName: String { (path as NSString).lastPathComponent }
    }

    struct Project {
        let folder: String
        /// The repository root, or `folder` outside a repository.
        let root: String
        /// Claude Code's memory folder for it, existing or not.
        let claudeFolder: String
        var notes: [Note]

        var name: String { (root as NSString).lastPathComponent }
        func notes(from source: Note.Source) -> [Note] { notes.filter { $0.source == source } }
    }

    static var home: String { HookInstaller.home }

    // MARK: Reading

    /// Everything remembered for `folder`. Runs git and reads files: call off the main thread.
    static func load(folder: String) -> Project {
        let root = AgentTools.repoRoot(of: folder) ?? folder
        let claudeFolder = claudeMemoryFolder(for: root) ?? claudeMemoryFolder(for: folder)
            ?? (home + "/.claude/projects/" + encode(root) + "/memory")
        var notes = claudeNotes(in: claudeFolder)
        notes += codexGroups(for: root)
        notes += instructionFiles(root: root, folder: folder)
        return Project(folder: folder, root: root, claudeFolder: claudeFolder, notes: notes)
    }

    /// Claude Code names a project's folder after its path, with everything but letters and
    /// digits turned into dashes.
    static func encode(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// The existing memory folder for `path`. Matched without case, since the same folder can
    /// be reached as `~/Projects/App` and `~/projects/app`.
    static func claudeMemoryFolder(for path: String) -> String? {
        let projects = home + "/.claude/projects"
        let wanted = encode(path).lowercased()
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return nil }
        let matches = names.filter { $0.lowercased() == wanted }
            .map { projects + "/" + $0 + "/memory" }
            .filter { FileManager.default.fileExists(atPath: $0) }
        // Several spellings: the one with the most notes.
        return matches.max { (noteFiles(in: $0).count) < (noteFiles(in: $1).count) }
    }

    private static func noteFiles(in folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasSuffix(".md") && $0 != "MEMORY.md" }
            .sorted()
    }

    static func claudeNotes(in folder: String) -> [Note] {
        noteFiles(in: folder).compactMap { name in
            let path = folder + "/" + name
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            let (fields, body) = frontMatter(raw)
            return Note(source: .claude, path: path, anchor: nil,
                        title: fields["name"].map(humanize) ?? humanize((name as NSString).deletingPathExtension),
                        summary: fields["description"] ?? firstLine(body),
                        kind: fields["type"] ?? "note",
                        body: body, raw: raw, modified: modified(path))
        }
        .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    /// Codex's task groups whose `applies_to: cwd=` is this project or inside it.
    static func codexGroups(for root: String) -> [Note] {
        let path = home + "/.codex/memories/MEMORY.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let date = modified(path)
        let wanted = root.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ("\n" + text).components(separatedBy: "\n# Task Group: ").dropFirst().compactMap { group in
            let lines = group.components(separatedBy: "\n")
            guard let heading = lines.first?.trimmingCharacters(in: .whitespaces), !heading.isEmpty,
                  let applies = lines.first(where: { $0.hasPrefix("applies_to:") }),
                  let cwd = applies.range(of: #"cwd=[^;]+"#, options: .regularExpression)
                    .map({ String(applies[$0].dropFirst(4)).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }),
                  cwd == wanted || cwd.hasPrefix(wanted + "/") else { return nil }
            let scope = lines.first { $0.hasPrefix("scope:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return Note(source: .codex, path: path, anchor: heading, title: heading,
                        summary: scope ?? firstLine(body), kind: "task group",
                        body: body, raw: "# Task Group: " + group, modified: date)
        }
    }

    static func instructionFiles(root: String, folder: String) -> [Note] {
        var candidates: [(String, String)] = []
        for dir in Array(Set([root, folder])).sorted() {
            candidates += [(dir + "/CLAUDE.md", "Claude Code, every session"),
                           (dir + "/CLAUDE.local.md", "Claude Code, this Mac only"),
                           (dir + "/.claude/CLAUDE.md", "Claude Code, every session"),
                           (dir + "/AGENTS.md", "Codex, every session")]
        }
        candidates += [(home + "/.claude/CLAUDE.md", "Claude Code, every project"),
                       (home + "/.codex/AGENTS.md", "Codex, every project")]
        var seen = Set<String>()
        return candidates.compactMap { path, role in
            guard seen.insert(path.lowercased()).inserted,
                  let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            let shown = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : (path as NSString).abbreviatingWithTildeInPath
            return Note(source: .instructions, path: path, anchor: nil, title: shown,
                        summary: role, kind: "instructions", body: raw, raw: raw, modified: modified(path))
        }
    }

    // MARK: Changing

    enum EditError: LocalizedError {
        case readOnly
        case changedOnDisk

        var errorDescription: String? {
            switch self {
            case .readOnly: return "Codex manages its own memories; change them by telling Codex."
            case .changedOnDisk: return "The file changed since it was opened. Reload it, then make your change again."
            }
        }
    }

    /// Writes `text` over the note's file, unless the file changed since `note` was read.
    static func save(_ note: Note, text: String) throws {
        guard note.editable else { throw EditError.readOnly }
        let current = try? String(contentsOfFile: note.path, encoding: .utf8)
        guard current == note.raw else { throw EditError.changedOnDisk }
        try text.write(toFile: note.path, atomically: true, encoding: .utf8)
    }

    /// Deletes a Claude Code note and its line in `MEMORY.md`. Instruction files are only
    /// edited here, never deleted.
    static func delete(_ note: Note) throws {
        guard note.source == .claude else { throw EditError.readOnly }
        try FileManager.default.removeItem(atPath: note.path)
        let index = ((note.path as NSString).deletingLastPathComponent as NSString).appendingPathComponent("MEMORY.md")
        guard let text = try? String(contentsOfFile: index, encoding: .utf8) else { return }
        let link = "(" + note.fileName + ")"
        let kept = text.components(separatedBy: "\n").filter { !$0.contains(link) }.joined(separator: "\n")
        if kept != text { try kept.write(toFile: index, atomically: true, encoding: .utf8) }
    }

    // MARK: Sharing

    /// The notes `from` keeps about `folder`, for another agent: in a handoff, or (through
    /// the hooks) at the start of the other agent's sessions. Nil when there are none.
    static func sharedText(folder: String, from agent: VerticalTabAgentKind, limit: Int = 8_000) -> String? {
        let project = load(folder: folder)
        var parts: [String] = []
        switch agent {
        case .codex:
            for note in project.notes(from: .codex) { parts.append("### \(note.title)\n\n\(note.body)") }
            if let agents = project.notes(from: .instructions).first(where: { $0.path == project.root + "/AGENTS.md" }) {
                parts.append("### AGENTS.md\n\n\(agents.body)")
            }
        case .claude:
            for note in project.notes(from: .claude) {
                parts.append("### \(note.title) (\(note.kind))\n\n\(note.body.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if let claude = project.notes(from: .instructions).first(where: { $0.path == project.root + "/CLAUDE.md" }) {
                parts.append("### CLAUDE.md\n\n\(claude.body)")
            }
        default:
            return nil
        }
        guard !parts.isEmpty else { return nil }
        return AgentTools.clip(parts.joined(separator: "\n\n"), limit)
    }

    // MARK: Helpers

    /// Splits a `---` header of `key: value` lines (nested ones flattened) from the text.
    static func frontMatter(_ raw: String) -> ([String: String], String) {
        guard raw.hasPrefix("---\n") else { return ([:], raw) }
        let rest = raw.dropFirst(4)
        guard let end = rest.range(of: "\n---") else { return ([:], raw) }
        var fields: [String: String] = [:]
        for line in rest[..<end.lowerBound].components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty, !value.isEmpty, fields[key] == nil { fields[key] = value }
        }
        let body = rest[end.upperBound...].drop { $0 != "\n" }
        return (fields, String(body).trimmingCharacters(in: .newlines))
    }

    private static func humanize(_ slug: String) -> String {
        guard !slug.contains(" ") else { return slug }
        let words = slug.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = words.first else { return slug }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) } ?? ""
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
#endif
