#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Best-of-N: several agents take the same task at once, each in its own git worktree (a
/// separate copy of the project on its own branch), so they can't interfere with each other
/// or with the user's files. Their results are compared side by side, and the chosen one's
/// changes are applied to the real project.
struct AgentRace: Codable, Identifiable, Equatable {
    struct Contestant: Codable, Identifiable, Equatable {
        /// e.g. "claude-1".
        let id: String
        let agent: String
        let worktree: String
        let branch: String
        /// Commit holding the starting point (HEAD plus any uncommitted changes that were copied in).
        let baseline: String

        var kind: VerticalTabAgentKind { VerticalTabAgentKind(id: agent) }
        var name: String {
            let number = id.split(separator: "-").last.map(String.init) ?? ""
            return "\(kind.displayName) \(number)"
        }
    }

    let id: String
    let task: String
    let repoRoot: String
    let directory: String
    let created: Date
    let contestants: [Contestant]

    var repoName: String { (repoRoot as NSString).lastPathComponent }
}

/// Changes one contestant has made since the baseline.
struct AgentRaceDiff: Equatable {
    var files: [(path: String, added: Int, removed: Int)] = []
    var text = ""
    var error: String?

    var added: Int { files.reduce(0) { $0 + $1.added } }
    var removed: Int { files.reduce(0) { $0 + $1.removed } }

    static func == (a: AgentRaceDiff, b: AgentRaceDiff) -> Bool {
        a.text == b.text && a.error == b.error && a.files.map(\.path) == b.files.map(\.path)
    }
}

final class AgentRaces: ObservableObject {
    static let shared = AgentRaces()

    @Published private(set) var races: [AgentRace] = []
    /// Contestant tabs opened in this run of the app, by race id + contestant id.
    private var tabs: [String: Weak<TerminalController>] = [:]
    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-custom.races", qos: .userInitiated)

    static var directory: URL { AgentTools.root.appendingPathComponent("races", isDirectory: true) }

    private init() {
        load()
    }

    /// Races survive restarts (their worktrees are on disk), so they can still be compared and cleaned up.
    private func load() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        races = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("race.json")) else { return nil }
            return try? decoder.decode(AgentRace.self, from: data)
        }.sorted { $0.created > $1.created }
    }

    func controller(for race: AgentRace, _ contestant: AgentRace.Contestant) -> TerminalController? {
        tabs["\(race.id)/\(contestant.id)"]?.value
    }

    func activity(for race: AgentRace, _ contestant: AgentRace.Contestant) -> VerticalTabAgentInfo? {
        guard let controller = controller(for: race, contestant) else { return nil }
        return controller.surfaceTree.lazy.compactMap { VerticalTabsAgents.shared.info(for: $0) }.first
    }

    // MARK: Starting

    /// Creates a worktree per contestant, then opens a tab for each running its agent on the task.
    func start(task: String, folder: String, counts: [VerticalTabAgentKind: Int], includeChanges: Bool,
               from owner: TerminalController, completion: @escaping (Result<AgentRace, RaceError>) -> Void) {
        queue.async {
            let result = Self.prepare(task: task, folder: folder, counts: counts, includeChanges: includeChanges)
            DispatchQueue.main.async {
                if case .success(let race) = result {
                    self.races.insert(race, at: 0)
                    self.openTabs(for: race, from: owner)
                }
                completion(result)
            }
        }
    }

    struct RaceError: Error { let message: String }

    private static func prepare(task: String, folder: String, counts: [VerticalTabAgentKind: Int],
                                includeChanges: Bool) -> Result<AgentRace, RaceError> {
        guard let root = AgentTools.repoRoot(of: folder) else {
            return .failure(RaceError(message: "This folder isn't in a git repository. Races need git to make separate copies (run `git init` and make a commit first)."))
        }
        let head = AgentTools.git(["rev-parse", "HEAD"], in: root)
        guard head.ok else {
            return .failure(RaceError(message: "The repository has no commits yet. Make a first commit, then start the race."))
        }
        let headSHA = head.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Uncommitted work: tracked changes as a stash commit, untracked files copied over.
        let stash = includeChanges
            ? AgentTools.git(["stash", "create"], in: root).output.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let untracked = includeChanges
            ? AgentTools.git(["ls-files", "--others", "--exclude-standard", "-z"], in: root).output
                .split(separator: "\0").map(String.init) : []

        let stamp = AgentTools.timestamp()
        let id = "\((root as NSString).lastPathComponent)-\(stamp)"
        let dir = directory.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            return .failure(RaceError(message: "Couldn't create \(dir.path): \(error.localizedDescription)"))
        }

        var contestants: [AgentRace.Contestant] = []
        for kind in AgentHandoff.targets {
            for n in 0..<(counts[kind] ?? 0) {
                let cid = "\(kind.rawValue)-\(n + 1)"
                let worktree = dir.appendingPathComponent(cid).path
                let branch = "race/\(stamp)/\(cid)"
                let add = AgentTools.git(["worktree", "add", "-q", "-b", branch, worktree, headSHA], in: root)
                guard add.ok else {
                    return .failure(RaceError(message: "git worktree failed: \(add.error)"))
                }
                if !stash.isEmpty {
                    AgentTools.git(["stash", "apply", "--quiet", stash], in: worktree)
                }
                for path in untracked {
                    let target = (worktree as NSString).appendingPathComponent(path)
                    try? fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true)
                    try? fm.copyItem(atPath: (root as NSString).appendingPathComponent(path), toPath: target)
                }
                // Commit the starting point so each agent's diff shows only its own work.
                AgentTools.git(["add", "-A"], in: worktree)
                AgentTools.git(["-c", "user.name=Ghostty Custom", "-c", "user.email=race@ghostty-custom.local",
                                "commit", "-q", "--no-verify", "--allow-empty", "-m", "Race baseline"], in: worktree)
                let baseline = AgentTools.git(["rev-parse", "HEAD"], in: worktree).output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                contestants.append(.init(id: cid, agent: kind.rawValue, worktree: worktree, branch: branch, baseline: baseline))
            }
        }

        let prompt = """
        \(task)

        (You're one of several agents working on this same task independently, each in a separate copy of the \
        project. Work only inside this folder. When you're done, give a short summary of what you changed and why.)
        """
        try? prompt.write(to: dir.appendingPathComponent("task.md"), atomically: true, encoding: .utf8)

        let race = AgentRace(id: id, task: task, repoRoot: root, directory: dir.path, created: Date(), contestants: contestants)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(race).write(to: dir.appendingPathComponent("race.json"))
        return .success(race)
    }

    private func openTabs(for race: AgentRace, from owner: TerminalController) {
        let promptFile = URL(fileURLWithPath: race.directory).appendingPathComponent("task.md")
        for contestant in race.contestants {
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = contestant.worktree
            config.initialInput = AgentTools.agentCommand(contestant.kind, promptFile: promptFile)
            guard let controller = TerminalController.newTab(owner.ghostty, from: owner.window, withBaseConfig: config) else { continue }
            controller.titleOverride = "Race · \(contestant.name)"
            (controller.window as? TerminalWindow)?.tabColor = .purple
            tabs["\(race.id)/\(contestant.id)"] = Weak(controller)
        }
        // Stay on the tab the race was started from; the compare window shows progress.
        owner.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Comparing

    /// Everything the contestant changed since the baseline, including new files. Doesn't touch
    /// git's index, so it's safe while the agent is still working.
    func diff(_ contestant: AgentRace.Contestant, completion: @escaping (AgentRaceDiff) -> Void) {
        queue.async {
            let result = Self.computeDiff(contestant, binary: false)
            DispatchQueue.main.async { completion(result.diff) }
        }
    }

    private static func computeDiff(_ c: AgentRace.Contestant, binary: Bool) -> (diff: AgentRaceDiff, patch: String) {
        var diff = AgentRaceDiff()
        guard FileManager.default.fileExists(atPath: c.worktree) else {
            diff.error = "This copy was deleted."
            return (diff, "")
        }
        let flags = binary ? ["--binary"] : ["--no-color"]
        var patch = AgentTools.git(["diff"] + flags + [c.baseline], in: c.worktree).output
        for line in AgentTools.git(["diff", "--numstat", c.baseline], in: c.worktree).output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            diff.files.append((String(parts[2]), Int(parts[0]) ?? 0, Int(parts[1]) ?? 0))
        }
        let untracked = AgentTools.git(["ls-files", "--others", "--exclude-standard", "-z"], in: c.worktree).output
            .split(separator: "\0").map(String.init)
        for path in untracked.prefix(200) {
            let added = AgentTools.git(["diff", "--no-index"] + flags + ["/dev/null", path], in: c.worktree).output
            patch += added
            let lines = added.split(separator: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
            diff.files.append((path, lines, 0))
        }
        diff.text = binary ? "" : AgentTools.clip(patch, 400_000)
        return (diff, patch)
    }

    /// Applies the contestant's changes to the real project's working tree.
    func keep(_ contestant: AgentRace.Contestant, of race: AgentRace, completion: @escaping (String?) -> Void) {
        queue.async {
            let patch = Self.computeDiff(contestant, binary: true).patch
            guard !patch.isEmpty else {
                DispatchQueue.main.async { completion("\(contestant.name) hasn't changed anything yet.") }
                return
            }
            let file = URL(fileURLWithPath: race.directory).appendingPathComponent("\(contestant.id).patch")
            try? patch.write(to: file, atomically: true, encoding: .utf8)
            let result = AgentTools.git(["apply", "--whitespace=nowarn", file.path], in: race.repoRoot)
            DispatchQueue.main.async {
                completion(result.ok ? nil : """
                The changes don't apply cleanly to your project (it probably changed since the race started).

                \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))

                The patch is saved at \(file.path), and the work is on branch \(contestant.branch).
                """)
            }
        }
    }

    /// Opens Claude Code in the project with a prompt to compare every contestant's work.
    func judge(_ race: AgentRace, from owner: TerminalController) {
        let entries = race.contestants.map {
            "- \($0.name): folder \($0.worktree), compare with `git -C \(AgentTools.shellQuote($0.worktree)) diff \($0.baseline)` plus any new untracked files"
        }.joined(separator: "\n")
        let prompt = """
        Several coding agents each solved the same task independently, in separate copies of this project.

        The task:
        \(race.task)

        Their work:
        \(entries)

        Compare the solutions. For each one, say what it does well and what's wrong or risky (bugs, missing edge \
        cases, unnecessary changes). Then recommend which one to keep and why, and anything worth borrowing from \
        the others. Don't modify any files.
        """
        guard let file = AgentTools.writePrompt(prompt, folder: "races/\(race.id)", name: "judge.md") else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = race.repoRoot
        config.initialInput = AgentTools.agentCommand(.claude, promptFile: file)
        if let controller = TerminalController.newTab(owner.ghostty, from: owner.window, withBaseConfig: config) {
            controller.titleOverride = "Race · Judge"
            (controller.window as? TerminalWindow)?.tabColor = .purple
        }
    }

    /// Closes the race's tabs, deletes its worktrees and branches, and forgets it.
    func cleanUp(_ race: AgentRace) {
        for contestant in race.contestants {
            controller(for: race, contestant)?.closeTab(nil)
            tabs.removeValue(forKey: "\(race.id)/\(contestant.id)")
        }
        races.removeAll { $0.id == race.id }
        queue.async {
            for contestant in race.contestants {
                AgentTools.git(["worktree", "remove", "--force", contestant.worktree], in: race.repoRoot)
                AgentTools.git(["branch", "-D", contestant.branch], in: race.repoRoot)
            }
            AgentTools.git(["worktree", "prune"], in: race.repoRoot)
            try? FileManager.default.removeItem(atPath: race.directory)
        }
    }
}

// MARK: - Windows

/// Keeps one window per id for Mission Control and races.
enum AgentToolWindows {
    private static var windows: [String: NSWindow] = [:]

    static func show<V: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[id] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            windows.removeValue(forKey: id)
            // Drop the SwiftUI view (and its timers) with the window.
            DispatchQueue.main.async { window.contentView = nil }
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func close(id: String) {
        windows[id]?.close()
    }

    static func isOpen(_ id: String) -> Bool {
        windows[id]?.isVisible == true
    }
}

extension AgentRaces {
    static func showSetup(from owner: TerminalController) {
        AgentToolWindows.show(id: "race-setup", title: "Race Agents", size: NSSize(width: 520, height: 430)) {
            AgentRaceSetupView(owner: owner, folder: owner.focusedSurface?.pwd)
        }
    }

    static func show(_ race: AgentRace, from owner: TerminalController?) {
        AgentToolWindows.show(id: "race-\(race.id)", title: "Race · \(race.repoName)", size: NSSize(width: 1180, height: 760)) {
            AgentRaceView(race: race, owner: owner)
        }
    }
}

// MARK: - Setup

private struct AgentRaceSetupView: View {
    let owner: TerminalController
    let folder: String?

    @State private var task = ""
    @State private var claude = 1
    @State private var codex = 1
    @State private var includeChanges = true
    @State private var starting = false
    @State private var error: String?

    private var total: Int { claude + codex }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed").font(.system(size: 22)).foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Race agents").font(.system(size: 17, weight: .semibold))
                    Text("Each agent gets its own copy of the project. Compare the results and keep the best.")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Task").font(.system(size: 12, weight: .semibold))
                TextEditor(text: $task)
                    .font(.system(size: 13))
                    .frame(height: 110)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }
            HStack(spacing: 18) {
                contestantStepper(.claude, value: $claude)
                contestantStepper(.codex, value: $codex)
            }
            Toggle("Include my uncommitted changes", isOn: $includeChanges)
                .font(.system(size: 12))
            Text("Project: \(folder.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "unknown folder")")
                .font(.system(size: 11)).foregroundColor(.secondary)
            if let error {
                Text(error).font(.system(size: 12)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { AgentToolWindows.close(id: "race-setup") }
                    .keyboardShortcut(.cancelAction)
                Button(starting ? "Setting up…" : "Start race (\(total) agents)") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(starting || total < 2 || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folder == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400)
    }

    private func contestantStepper(_ kind: VerticalTabAgentKind, value: Binding<Int>) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().fill(kind.brandColor)
                VerticalTabAgentLogo(kind: kind, tint: kind.glyphOnBrand).frame(width: 11, height: 11)
            }
            .frame(width: 20, height: 20)
            Stepper("\(kind.displayName) × \(value.wrappedValue)", value: value, in: 0...3)
                .font(.system(size: 12))
        }
    }

    private func start() {
        guard let folder else { return }
        starting = true
        error = nil
        let task = self.task.trimmingCharacters(in: .whitespacesAndNewlines)
        AgentRaces.shared.start(task: task, folder: folder, counts: [.claude: claude, .codex: codex],
                                includeChanges: includeChanges, from: owner) { result in
            starting = false
            switch result {
            case .success(let race):
                AgentToolWindows.close(id: "race-setup")
                AgentRaces.show(race, from: owner)
            case .failure(let failure):
                error = failure.message
            }
        }
    }
}

// MARK: - Compare

private struct AgentRaceView: View {
    let race: AgentRace
    let owner: TerminalController?

    @ObservedObject private var races = AgentRaces.shared
    @State private var diffs: [String: AgentRaceDiff] = [:]
    @State private var message: String?
    @State private var tick = Date()
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 1) {
                ForEach(race.contestants) { contestant in
                    column(contestant)
                }
            }
            .background(Color.primary.opacity(0.08))
        }
        .frame(minWidth: 700, minHeight: 420)
        .onAppear(perform: refresh)
        .onReceive(timer) { now in
            tick = now
            refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag.checkered.2.crossed").font(.system(size: 20)).foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 3) {
                Text(race.task).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text("\(race.repoName) · started \(RelativeDateTimeFormatter().localizedString(for: race.created, relativeTo: tick))")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if let message {
                    Text(message).font(.system(size: 12)).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            Spacer()
            if let owner {
                Button {
                    AgentRaces.shared.judge(race, from: owner)
                } label: { Label("Ask Claude to judge", systemImage: "scalemass") }
            }
            Button(role: .destructive) { confirmCleanUp() } label: { Label("Clean up", systemImage: "trash") }
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    private func column(_ contestant: AgentRace.Contestant) -> some View {
        let diff = diffs[contestant.id]
        let info = races.activity(for: race, contestant)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(contestant.kind.brandColor)
                        VerticalTabAgentLogo(kind: contestant.kind, tint: contestant.kind.glyphOnBrand).frame(width: 12, height: 12)
                    }
                    .frame(width: 22, height: 22)
                    Text(contestant.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    AgentStatusPill(activity: info?.activity, closed: races.controller(for: race, contestant) == nil)
                }
                if let diff {
                    Text(diff.files.isEmpty ? "No changes yet" :
                            "\(diff.files.count) file\(diff.files.count == 1 ? "" : "s") · +\(diff.added) −\(diff.removed)")
                        .font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Keep this one") { keep(contestant) }
                        .disabled(diff?.files.isEmpty ?? true)
                    if let controller = races.controller(for: race, contestant) {
                        Button("Open tab") {
                            controller.window?.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .controlSize(.small)
            }
            .padding(12)
            Divider()
            AgentDiffView(text: diff?.text ?? "", error: diff?.error)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func refresh() {
        for contestant in race.contestants {
            AgentRaces.shared.diff(contestant) { diff in
                if diffs[contestant.id] != diff { diffs[contestant.id] = diff }
            }
        }
    }

    private func keep(_ contestant: AgentRace.Contestant) {
        let alert = NSAlert()
        alert.messageText = "Keep \(contestant.name)'s changes?"
        alert.informativeText = "Its changes will be applied to \(race.repoName). They'll show up as uncommitted changes you can review before committing."
        alert.addButton(withTitle: "Apply changes")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AgentRaces.shared.keep(contestant, of: race) { error in
            if let error {
                message = error
            } else {
                message = nil
                let done = NSAlert()
                done.messageText = "Applied \(contestant.name)'s changes to \(race.repoName)"
                done.informativeText = "Clean up the race now? This closes its tabs and deletes the other copies."
                done.addButton(withTitle: "Clean up")
                done.addButton(withTitle: "Keep race open")
                if done.runModal() == .alertFirstButtonReturn {
                    AgentRaces.shared.cleanUp(race)
                    AgentToolWindows.close(id: "race-\(race.id)")
                }
            }
        }
    }

    private func confirmCleanUp() {
        let alert = NSAlert()
        alert.messageText = "Clean up this race?"
        alert.informativeText = "Closes the race's tabs and deletes every copy and its branch. Your real project isn't touched. Changes you haven't kept are lost."
        alert.addButton(withTitle: "Clean up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        AgentRaces.shared.cleanUp(race)
        AgentToolWindows.close(id: "race-\(race.id)")
    }
}

/// A unified diff with added lines green, removed lines red and file headers emphasized.
struct AgentDiffView: View {
    let text: String
    let error: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if let error {
                        Text(error).font(.system(size: 12)).foregroundColor(.secondary).padding(12)
                    } else if text.isEmpty {
                        Text("Nothing changed yet.").font(.system(size: 12)).foregroundColor(.secondary).padding(12)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                row(line)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                // A two-way scroll view centers smaller content; pin it to the top left.
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }

    private var lines: [Substring] {
        Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(6000))
    }

    @ViewBuilder
    private func row(_ line: Substring) -> some View {
        if line.hasPrefix("diff --git") {
            let path = line.split(separator: " ").last.map { String($0.dropFirst(2)) } ?? String(line)
            Text(path)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.primary.opacity(0.08))
                .padding(.top, 6)
        } else if line.hasPrefix("index ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
                    || line.hasPrefix("new file") || line.hasPrefix("deleted file") {
            EmptyView()
        } else {
            let color: Color? = line.hasPrefix("+") ? .green : line.hasPrefix("-") ? .red : nil
            Text(line.isEmpty ? " " : String(line))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.hasPrefix("@@") ? .purple : color ?? .primary.opacity(0.85))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .background((color ?? .clear).opacity(0.12))
        }
    }
}

/// Colored status label for an agent, shared by the race view and Mission Control.
struct AgentStatusPill: View {
    let activity: VerticalTabAgentActivity?
    var closed = false

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var label: String {
        if closed { return "Tab closed" }
        return activity?.label ?? "Starting"
    }

    static func color(_ activity: VerticalTabAgentActivity?) -> Color {
        switch activity {
        case .working: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .needsPermission: return .orange
        case .needsInput: return .yellow
        case .done: return .green
        case .failed: return .red
        case .ready, .none: return .secondary
        }
    }

    private var color: Color { closed ? .secondary : Self.color(activity) }
}
#endif
