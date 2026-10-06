#if os(macOS)
import AppKit
import Combine

/// A snapshot of the project at the start of every agent turn, so a turn can be undone.
///
/// Snapshots are git tree objects written through a copy of the index (the same as Review's
/// baselines), so nothing about the repository changes: no commits, branches, refs or stash
/// entries, and the real index is untouched. Folders that aren't repositories use Review's
/// private shadow repository. Restoring first snapshots the current state, so a restore can
/// itself be undone.
final class TurnCheckpoints: ObservableObject {
    static let shared = TurnCheckpoints()

    struct Checkpoint: Identifiable, Equatable {
        let id: UUID
        let time: Date
        /// The prompt that started the turn, or what a restore point was taken before.
        let title: String
        let agent: VerticalTabAgentKind?
        let repoRoot: String
        let gitDir: String?
        let tree: String
        /// Taken just before a restore: going back to it undoes the restore.
        let isRestorePoint: Bool
    }

    /// Newest last, per pane.
    @Published private(set) var checkpoints: [ObjectIdentifier: [Checkpoint]] = [:]

    private var lastActivity: [ObjectIdentifier: VerticalTabAgentActivity] = [:]
    private var taking: Set<ObjectIdentifier> = []
    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-extreme.checkpoints", qos: .utility)
    private var cancellables: Set<AnyCancellable> = []
    private let maxPerPane = 30

    /// Starts listening for agent turns. Called once at launch.
    static func start() { _ = shared }

    private init() {
        NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                if let surface = note.object as? Ghostty.SurfaceView { self?.agentChanged(surface) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let controller = (note.object as? NSWindow)?.windowController as? TerminalController else { return }
                for surface in controller.surfaceTree { self?.forget(ObjectIdentifier(surface)) }
            }
            .store(in: &cancellables)
    }

    func list(for surface: Ghostty.SurfaceView) -> [Checkpoint] {
        checkpoints[ObjectIdentifier(surface)] ?? []
    }

    /// The start of the agent's most recent turn.
    func lastTurn(for surface: Ghostty.SurfaceView) -> Checkpoint? {
        list(for: surface).last { !$0.isRestorePoint }
    }

    private func forget(_ key: ObjectIdentifier) {
        checkpoints.removeValue(forKey: key)
        lastActivity.removeValue(forKey: key)
    }

    // MARK: Taking checkpoints

    /// A turn starts when the agent goes to work after being anything else.
    private func agentChanged(_ surface: Ghostty.SurfaceView) {
        let key = ObjectIdentifier(surface)
        let info = VerticalTabsAgents.shared.info(for: surface)
        let previous = lastActivity[key]
        lastActivity[key] = info?.activity
        guard let info, info.kind != .hermes, info.activity == .working,
              previous != .working, previous != .needsPermission, let folder = surface.pwd else { return }
        take(for: surface, folder: folder, title: info.task ?? "Agent turn", agent: info.kind)
    }

    private func take(for surface: Ghostty.SurfaceView, folder: String, title: String, agent: VerticalTabAgentKind) {
        let key = ObjectIdentifier(surface)
        guard !taking.contains(key) else { return }
        taking.insert(key)
        let time = Date()
        queue.async {
            let place = Self.place(of: folder)
            let tree = place.flatMap { ReviewInbox.snapshot($0.root, gitDir: $0.gitDir) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.taking.remove(key)
                guard let place, let tree else { return }
                // Nothing changed since the last turn started: one checkpoint covers both.
                if let last = self.checkpoints[key]?.last, last.tree == tree, !last.isRestorePoint { return }
                self.append(Checkpoint(id: UUID(), time: time, title: title, agent: agent, repoRoot: place.root,
                                       gitDir: place.gitDir, tree: tree, isRestorePoint: false), to: key)
            }
        }
    }

    private func append(_ checkpoint: Checkpoint, to key: ObjectIdentifier) {
        var list = checkpoints[key] ?? []
        list.append(checkpoint)
        if list.count > maxPerPane { list.removeFirst(list.count - maxPerPane) }
        checkpoints[key] = list
    }

    /// The repository to snapshot, or Review's shadow repository for a plain folder.
    private static func place(of folder: String) -> (root: String, gitDir: String?)? {
        if let root = AgentTools.repoRoot(of: folder) { return (root, nil) }
        if let shadow = ReviewInbox.shadowRepo(for: folder) { return (folder, shadow) }
        return nil
    }

    // MARK: Restoring

    /// One file that restoring changes.
    struct Change {
        enum Kind { case restore, delete }
        let path: String
        let kind: Kind
    }

    /// Asks, then puts the project's files back to how they were at `checkpoint`.
    func confirmAndRestore(_ checkpoint: Checkpoint, on surface: Ghostty.SurfaceView) {
        if let info = VerticalTabsAgents.shared.info(for: surface),
           info.activity == .working || info.activity == .needsPermission {
            let alert = NSAlert()
            alert.messageText = "\(info.kind.displayName) is still working"
            alert.informativeText = "Wait for it to finish, or stop it (Esc in its pane), before restoring files."
            alert.runModal()
            return
        }
        queue.async {
            let current = ReviewInbox.snapshot(checkpoint.repoRoot, gitDir: checkpoint.gitDir)
            let changes = current.map { Self.changes(from: checkpoint, to: $0) } ?? []
            DispatchQueue.main.async { [weak self, weak surface] in
                guard let self, let surface else { return }
                guard let current else {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't read the project's current files"
                    alert.runModal()
                    return
                }
                DemoDirector.note("restore: \(changes.count) changes, current \(current.prefix(8))")
                guard !changes.isEmpty else {
                    let alert = NSAlert()
                    alert.messageText = "Nothing to restore"
                    alert.informativeText = "The files are already the same as they were at that point."
                    alert.runModal()
                    return
                }
                guard self.confirm(checkpoint, changes: changes) else { return }
                // The current state first, so this restore can be undone.
                self.append(Checkpoint(id: UUID(), time: Date(), title: "Before restoring “\(Self.short(checkpoint.title))”",
                                       agent: nil, repoRoot: checkpoint.repoRoot, gitDir: checkpoint.gitDir,
                                       tree: current, isRestorePoint: true), to: ObjectIdentifier(surface))
                self.queue.async { Self.apply(changes, from: checkpoint) }
            }
        }
    }

    private func confirm(_ checkpoint: Checkpoint, changes: [Change]) -> Bool {
        DemoDirector.note("restore: asking about \(changes.map(\.path).joined(separator: ", "))")
        let alert = NSAlert()
        alert.messageText = checkpoint.isRestorePoint
            ? "Undo the restore?"
            : "Restore files to before “\(Self.short(checkpoint.title))”?"
        let listed = changes.prefix(6).map { "\($0.kind == .delete ? "Delete" : "Restore") \($0.path)" }
        let more = changes.count > 6 ? "\n… and \(changes.count - 6) more" : ""
        alert.informativeText = "\(changes.count) file\(changes.count == 1 ? "" : "s") will change:\n"
            + listed.joined(separator: "\n") + more
            + "\n\nYour current files are saved first, so you can undo this from the same menu."
        alert.alertStyle = .warning
        // Restoring overwrites files: it takes a click, and Return cancels.
        let restore = alert.addButton(withTitle: "Restore")
        restore.keyEquivalent = ""
        restore.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        let response = alert.runModal()
        DemoDirector.note("restore: dialog returned \(response.rawValue)")
        return response == .alertFirstButtonReturn
    }

    /// What has to change for the files to match `checkpoint` again.
    private static func changes(from checkpoint: Checkpoint, to current: String) -> [Change] {
        guard checkpoint.tree != current else { return [] }
        let output = ReviewInbox.git(["diff", "--name-status", "--no-renames", "-z", checkpoint.tree, current],
                                     in: checkpoint.repoRoot, gitDir: checkpoint.gitDir).output
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var changes: [Change] = []
        var index = 0
        while index + 1 < fields.count {
            let status = fields[index], path = fields[index + 1]
            index += 2
            // Added since the checkpoint: it didn't exist then.
            changes.append(Change(path: path, kind: status.hasPrefix("A") ? .delete : .restore))
        }
        return changes
    }

    private static func apply(_ changes: [Change], from checkpoint: Checkpoint) {
        let fm = FileManager.default
        let root = checkpoint.repoRoot
        for change in changes where change.kind == .delete {
            let path = (root as NSString).appendingPathComponent(change.path)
            try? fm.removeItem(atPath: path)
            removeEmptyParents(of: path, below: root)
        }
        let restores = changes.filter { $0.kind == .restore }.map(\.path)
        // Working tree only: the index and HEAD stay as they are.
        stride(from: 0, to: restores.count, by: 200).forEach { start in
            let chunk = Array(restores[start..<min(start + 200, restores.count)])
            ReviewInbox.git(["restore", "--source=\(checkpoint.tree)", "--worktree", "--"] + chunk,
                            in: root, gitDir: checkpoint.gitDir)
        }
    }

    private static func removeEmptyParents(of path: String, below root: String) {
        var dir = (path as NSString).deletingLastPathComponent
        while dir.count > root.count, dir.hasPrefix(root + "/"),
              (try? FileManager.default.contentsOfDirectory(atPath: dir))?.isEmpty == true {
            try? FileManager.default.removeItem(atPath: dir)
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    static func short(_ text: String, _ limit: Int = 48) -> String {
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}
#endif
