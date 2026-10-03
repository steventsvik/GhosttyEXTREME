#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Places the vertical tabs sidebar to the left of the terminal content.
struct VerticalTabsLayout<Content: View>: View {
    let controller: TerminalController
    @ObservedObject var ghostty: Ghostty.App
    @StateObject private var model: VerticalTabsModel
    @StateObject private var overlay = VerticalTabsOverlayState()
    @ObservedObject private var editorPanel = EditorPanel.shared
    @ObservedObject private var hermes = HermesSessions.shared
    @ObservedObject private var commandBlocks = CommandBlocksPanel.shared
    @ObservedObject private var visualFix = VisualFixPanel.shared
    /// Pauses the chrome's animations while this window (tab) isn't on screen.
    @StateObject private var motion = WindowMotion()
    @AppStorage(EditorPanel.widthKey) private var editorWidth: Double = EditorPanel.defaultWidth
    @AppStorage(VisualFixPanel.widthKey) private var visualFixWidth: Double = VisualFixPanel.defaultWidth
    @AppStorage(AgentAurora.enabledKey) private var aurora = false
    @AppStorage(VerticalTabs.visibleKey) private var visible: Bool = true
    @AppStorage(VerticalTabs.widthKey) private var width: Double = VerticalTabs.defaultWidth
    private let content: Content

    init(controller: TerminalController, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.controller = controller
        self.ghostty = ghostty
        self._model = StateObject(wrappedValue: VerticalTabsModel(owner: controller))
        self.content = content()
    }

    /// The terminal never gets narrower than this to make room for side panels.
    private var minTerminalWidth: CGFloat { 320 }

    var body: some View {
        // Side panels have set widths; when the window is narrower than they need (macOS can
        // hand a window back smaller, e.g. from Stage Manager), the editor gives way so
        // nothing is pushed past the window's edge.
        GeometryReader { geometry in
            let limits = panelLimits(in: geometry.size.width)
            layout(maxEditorWidth: limits.editor, maxVisualFixWidth: limits.visualFix)
        }
        .environment(\.extremeMotion, motion.active)
        .onAppear { motion.attach(controller.window) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in motion.attach(controller.window) }
    }

    /// The most room the editor and Visual Fix can each have. When both want more than the
    /// window has, they share it in proportion.
    private func panelLimits(in total: CGFloat) -> (editor: CGFloat, visualFix: CGFloat) {
        let sidebar = visible && ghostty.readiness == .ready ? CGFloat(width) + 1 : 0
        let history: CGFloat = commandBlocks.isVisible(controller) ? 400 : 0
        let available = max(0, total - sidebar - history - minTerminalWidth - 2)
        let editor = editorPanel.isVisible(controller) ? CGFloat(editorWidth) : 0
        let fix = visualFix.isVisible(controller) ? CGFloat(visualFixWidth) : 0
        guard editor + fix > available, editor + fix > 0 else { return (max(240, available), max(360, available)) }
        let scale = available / (editor + fix)
        return (max(240, editor * scale), max(300, fix * scale))
    }

    private func layout(maxEditorWidth: CGFloat, maxVisualFixWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if visible && ghostty.readiness == .ready {
                VerticalTabsSidebar(model: model, owner: controller, config: ghostty.config)
                    .frame(width: width)
                    .environmentObject(overlay)
                VerticalTabsResizeHandle(width: $width)
            }
            // A Hermes tab shows Hermes's own app over its (hidden, idle) terminal.
            ZStack {
                content
                if hermes.isHermes(controller) {
                    HermesSessionView(controller: controller)
                }
                // Light behind the terminal that follows the tab's agents.
                if aurora, !hermes.isHermes(controller) {
                    AgentAurora(controller: controller)
                }
                // "Your app is live" when a localhost session starts listening.
                LocalhostToastLayer(controller: controller)
                // Branding: pixel corner brackets (a traveling light while an agent works)
                // and the sigil assembling when the tab opens.
                TerminalFrameOverlay(controller: controller)
                NewTabSplash()
            }
            // Each tab has its own editor.
            if editorPanel.isVisible(controller) {
                EditorPanelColumn(controller: controller, maxWidth: maxEditorWidth)
            }
            // Point at the running app and have the agent change it.
            if visualFix.isVisible(controller) {
                VisualFixColumn(controller: controller, maxWidth: maxVisualFixWidth)
            }
            if commandBlocks.isVisible(controller) {
                CommandBlocksColumn(controller: controller)
            }
        }
        .coordinateSpace(name: verticalTabsSpace)
        .overlay {
            if visible && ghostty.readiness == .ready {
                VerticalTabsOverlayLayer(
                    state: overlay,
                    palette: VerticalTabsPalette(config: ghostty.config),
                    sidebarWidth: width)
            }
        }
        .onChange(of: visible) { _ in overlay.dismissAll() }
        .onAppear {
            VerticalTabsMenu.shared.installIfNeeded()
            ReviewInbox.start()
            VerticalTabsTestSupport.openTestTabsIfRequested(from: controller)
        }
    }
}

/// Test-only: `GHOSTTY_EXTREME_TEST_TABS=N` (set by a test launch, never in normal use)
/// opens N tabs at startup so the sidebar can be exercised without UI scripting.
enum VerticalTabsTestSupport {
    private static var didOpen = false

    /// `GHOSTTY_EXTREME_TEST_OVERLAY=hover|menu`: the selected row opens its hover card
    /// or ⋮ menu shortly after launch.
    static let overlayMode = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_OVERLAY"]
    static let showOverlay = Notification.Name("com.steventsvik.ghostty-extreme.testShowOverlay")

    static func openTestTabsIfRequested(from controller: TerminalController) {
        guard !didOpen else { return }
        didOpen = true
        MainActor.assumeIsolated { DemoDirector.startIfRequested(from: controller) }
        if overlayMode != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NotificationCenter.default.post(name: showOverlay, object: nil)
            }
        }
        if let name = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_COLOR"],
           let color = TerminalTabColor.allCases.first(where: { $0.localizedName.lowercased() == name }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { (controller.window as? TerminalWindow)?.tabColor = color }
        }
        if ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_SESSION"] == "hermes" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NewSessionKind.hermes.open(from: controller) }
        }
        // `GHOSTTY_EXTREME_TEST_SESSION=docker:<kind>`: open an isolated Docker session.
        if let value = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_SESSION"], value.hasPrefix("docker:"),
           let kind = DockerSessionKind(rawValue: String(value.dropFirst("docker:".count))) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { DockerSessions.open(kind, from: controller) }
        }
        // `GHOSTTY_EXTREME_TEST_EDITOR_DELAY`: seconds before opening it (default 1.5).
        if let file = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_EDITOR"] {
            let delay = Double(ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_EDITOR_DELAY"] ?? "") ?? 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // A folder (trailing slash) opens the editor the way a user does, with no file.
                if file.hasSuffix("/") {
                    EditorPanel.shared.show(from: controller)
                } else {
                    EditorPanel.shared.show(from: controller, folder: (file as NSString).deletingLastPathComponent)
                    EditorPanel.shared.session(for: controller).webView.openFile(file, line: 20)
                }
                // `GHOSTTY_EXTREME_TEST_EDITOR_JS`: script run in the editor once it's loaded.
                if let script = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_EDITOR_JS"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        EditorPanel.shared.session(for: controller).webView.evaluateJavaScript(script)
                    }
                }
            }
        }
        // `GHOSTTY_EXTREME_TEST_BACKGROUND=<seconds>`: open the Background window then.
        if let value = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_BACKGROUND"], let delay = Double(value) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { HousekeepingWindow.show() }
        }
        // `GHOSTTY_EXTREME_TEST_VISUAL=<seconds>`: open Visual Fix on the best running app then.
        if let value = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_VISUAL"], let delay = Double(value) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { VisualFixPanel.shared.show(from: controller) }
        }
        // `GHOSTTY_EXTREME_TEST_PALETTE=1`: open the command palette in the visible tab after 11s.
        if ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_PALETTE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                let window = controller.window?.tabGroup?.selectedWindow ?? controller.window
                (window?.windowController as? BaseTerminalController)?.toggleCommandPalette(nil)
            }
        }
        let env = ProcessInfo.processInfo.environment
        // `GHOSTTY_EXTREME_TEST_TYPE=<command>`: types it (plus Enter) into the first tab after 3s.
        if let command = env["GHOSTTY_EXTREME_TEST_TYPE"] {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let model = controller.focusedSurface?.surfaceModel else { return }
                model.sendText(command)
                model.sendKeyEvent(.init(key: .enter, action: .press, text: "\r"))
                model.sendKeyEvent(.init(key: .enter, action: .release))
            }
        }
        // `GHOSTTY_EXTREME_TEST_REVIEW=comment,send,undo,commit`: acts on the first review item,
        // one step every 3s starting at 24s, logging to `GHOSTTY_EXTREME_TEST_LOG`.
        if let steps = env["GHOSTTY_EXTREME_TEST_REVIEW"] {
            let log: (String) -> Void = { line in
                guard let path = env["GHOSTTY_EXTREME_TEST_LOG"] else { return }
                let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 24_000_000_000)
                let inbox = ReviewInbox.shared
                for step in steps.split(separator: ",") {
                    guard let item = inbox.items.first else { log("\(step): no review item"); break }
                    switch step {
                    case "comment":
                        if let file = item.files.first, let line = file.hunks.first?.lines.first(where: { $0.kind == .added }) {
                            inbox.addComment("Use Decimal for money; floats round badly.", on: line, file: file, in: item)
                        }
                        log("comment: \(inbox.items.first?.comments.count ?? 0) comments")
                    case "send":
                        log("send: \(inbox.sendFeedback(item))")
                    case "undo":
                        if let file = item.files.first(where: { $0.status == .added }) { inbox.undo(file, in: item) }
                        log("undo: requested")
                    case "commit":
                        inbox.commit(item, message: "Add discount codes") { error in log("commit: \(error ?? "ok")") }
                    default:
                        break
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                log("files now: \(inbox.items.first?.files.map(\.path) ?? [])")
            }
        }
        // `GHOSTTY_EXTREME_TEST_OPEN=localhost,review,activity,blocks`: open those after
        // `GHOSTTY_EXTREME_TEST_OPEN_DELAY` seconds (default 10).
        if let windows = env["GHOSTTY_EXTREME_TEST_OPEN"] {
            let delay = Double(env["GHOSTTY_EXTREME_TEST_OPEN_DELAY"] ?? "") ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for name in windows.split(separator: ",") {
                    switch name {
                    case "localhost": LocalhostManager.show()
                    case "review": ReviewInbox.show()
                    case "activity": ActivityDashboard.toggle()
                    case "blocks": CommandBlocksPanel.shared.show(controller)
                    default: break
                    }
                }
            }
        }
        // `GHOSTTY_EXTREME_TEST_PRESENT=1`: after 8s, present the first tab's pane the way
        // Mission Control's Open does (while a later tab is selected).
        if env["GHOSTTY_EXTREME_TEST_PRESENT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                guard let surface = controller.surfaceTree.first else { return }
                NotificationCenter.default.post(name: Ghostty.Notification.ghosttyPresentTerminal, object: surface)
            }
        }
        // `GHOSTTY_EXTREME_TEST_MISSION=1`: open Mission Control after 12s.
        if env["GHOSTTY_EXTREME_TEST_MISSION"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { MissionControl.show() }
        }
        // `GHOSTTY_EXTREME_TEST_HANDOFF=review|continue`: hand the first pane off to Claude Code after 6s.
        if let mode = env["GHOSTTY_EXTREME_TEST_HANDOFF"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard let surface = controller.focusedSurface else { return }
                AgentHandoff.handOff(from: surface, in: controller, to: .claude, mode: mode == "continue" ? .continue : .review)
            }
        }
        // `GHOSTTY_EXTREME_TEST_RACE=<task>`: race one Claude and one Codex after 4s; with
        // `GHOSTTY_EXTREME_TEST_RACE_KEEP=1`, keep claude-1's changes at 30s and clean up at 36s,
        // logging to `GHOSTTY_EXTREME_TEST_LOG`.
        if let task = env["GHOSTTY_EXTREME_TEST_RACE"], let folder = env["GHOSTTY_EXTREME_TEST_RACE_FOLDER"] {
            let log: (String) -> Void = { line in
                guard let path = env["GHOSTTY_EXTREME_TEST_LOG"] else { return }
                let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                try? (old + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                AgentRaces.shared.start(task: task, folder: folder, counts: [.claude: 1, .codex: 1],
                                        includeChanges: true, from: controller) { result in
                    switch result {
                    case .failure(let error): log("race failed: \(error.message)")
                    case .success(let race):
                        log("race \(race.id) " + race.contestants.map { "\($0.id)=\($0.worktree)" }.joined(separator: " "))
                        AgentRaces.show(race, from: controller)
                        guard env["GHOSTTY_EXTREME_TEST_RACE_KEEP"] == "1" else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 26) {
                            AgentRaces.shared.keep(race.contestants[0], of: race) { error in
                                log("keep: \(error ?? "ok")")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                                    AgentRaces.shared.cleanUp(race)
                                    log("cleaned up")
                                }
                            }
                        }
                    }
                }
            }
        }
        // Report which window is the visible tab so a test can capture that one.
        if let path = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_WINDOW_FILE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let window = controller.window?.tabGroup?.selectedWindow ?? controller.window
                try? String(window?.windowNumber ?? 0).write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // `GHOSTTY_EXTREME_TEST_RESELECT=1`: switch back to the first tab after 9s and
        // report its window in <window file>.2.
        if ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_RESELECT"] == "1",
           let path = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_WINDOW_FILE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                VerticalTabsActions.select(controller)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    try? String(controller.window?.windowNumber ?? 0).write(toFile: path + ".2", atomically: true, encoding: .utf8)
                }
            }
        }
        guard let value = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_TABS"],
              let count = Int(value), count > 1 else { return }
        for i in 1..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 * Double(i)) {
                controller.newTab(nil)
            }
        }
    }
}

/// A thin draggable divider that resizes the sidebar.
private struct VerticalTabsResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(Extreme.line)
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        // Keep push/pop balanced so the cursor stack never leaks.
                        if inside, !cursorPushed {
                            NSCursor.resizeLeftRight.push()
                            cursorPushed = true
                        } else if !inside, cursorPushed {
                            NSCursor.pop()
                            cursorPushed = false
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                let proposed = start + value.translation.width
                                width = min(max(proposed, VerticalTabs.widthRange.lowerBound),
                                            VerticalTabs.widthRange.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            )
    }
}

/// Which tab groups are collapsed. Shared so every window's sidebar agrees.
final class VerticalTabsCollapse: ObservableObject {
    static let shared = VerticalTabsCollapse()
    @Published var collapsed: Set<ObjectIdentifier> = []

    func toggle(_ id: ObjectIdentifier) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }
}

struct VerticalTabsSidebar: View {
    @ObservedObject var model: VerticalTabsModel
    let owner: TerminalController
    let config: Ghostty.Config

    @AppStorage(VerticalTabs.condensedKey) private var condensed = false
    @ObservedObject private var collapse = VerticalTabsCollapse.shared
    @ObservedObject private var localhost = LocalhostSessions.shared
    @ObservedObject private var projects = VerticalTabsProjects.shared

    var body: some View {
        let palette = VerticalTabsPalette(config: config)
        // Localhost sessions get their own cards at the end, whatever their tab order.
        let isLocalhost: (VerticalTabEntry) -> Bool = { entry in
            entry.controller.map { localhost.session(for: $0) != nil } ?? false
        }
        let localhostTabs = model.tabs.filter(isLocalhost)

        VStack(spacing: 0) {
            header
            Rectangle().fill(Extreme.line).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ExtremeSectionLabel("Sessions") {
                        Text("\(model.tabs.count - localhostTabs.count)")
                            .font(Extreme.font(10)).foregroundColor(Extreme.dim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    ForEach(items(excluding: isLocalhost)) { item in
                        switch item {
                        case .tab(let index, let entry):
                            if let controller = entry.controller {
                                tabGroup(controller, entry: entry, index: index, palette: palette)
                                    .transition(.opacity)
                            }
                        case .project(let group, let members):
                            VerticalTabsProjectGroupView(
                                group: group,
                                controllers: members.compactMap(\.1.controller),
                                owner: owner
                            ) {
                                VStack(spacing: 6) {
                                    ForEach(members, id: \.1.id) { index, entry in
                                        if let controller = entry.controller {
                                            tabGroup(controller, entry: entry, index: index, palette: palette, inProject: true)
                                        }
                                    }
                                }
                            }
                            .transition(.asymmetric(insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                                                    removal: .opacity))
                        }
                    }
                }
                .padding(.bottom, 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: projects.groups)
            }

            // Localhost sessions stay in view, whatever else is open.
            if !localhostTabs.isEmpty {
                Rectangle().fill(Extreme.line).frame(height: 1)
                LocalhostSidebarSection(entries: localhostTabs, owner: owner)
            }

            // Things left running in the background that look finished (only when there are some).
            HousekeepingChip().padding(.horizontal, 8).padding(.bottom, 6)

            // Bottom left: live usage of the user's AI subscriptions.
            Rectangle().fill(Extreme.line).frame(height: 1)
            UsagePanel(palette: palette)
        }
        .background(sidebarBackground)
        .onAppear { Extreme.registerFonts() }
    }

    /// One sidebar entry: a tab on its own, or a project's tabs bracketed together.
    private enum Item: Identifiable {
        case tab(Int, VerticalTabEntry)
        case project(VerticalTabsProjects.Group, [(Int, VerticalTabEntry)])

        var id: String {
            switch self {
            case .tab(_, let entry): return "tab-\(entry.id.hashValue)"
            case .project(let group, _): return "project-" + group.id
            }
        }
    }

    /// Tabs in order, with each project's tabs gathered where its first tab is.
    private func items(excluding isLocalhost: (VerticalTabEntry) -> Bool) -> [Item] {
        var result: [Item] = []
        var placed: Set<String> = []
        let tabs = Array(model.tabs.enumerated()).filter { !isLocalhost($0.element) }
        for (offset, entry) in tabs {
            guard let controller = entry.controller else { continue }
            if let group = projects.group(for: controller) {
                guard placed.insert(group.id).inserted else { continue }
                let members = tabs.filter { $0.element.controller.map { group.members.contains(ObjectIdentifier($0)) } ?? false }
                result.append(.project(group, members.map { ($0.offset + 1, $0.element) }))
            } else {
                result.append(.tab(offset + 1, entry))
            }
        }
        return result
    }

    private func tabGroup(_ controller: TerminalController, entry: VerticalTabEntry, index: Int,
                          palette: VerticalTabsPalette, inProject: Bool = false) -> some View {
        VerticalTabGroup(
            controller: controller,
            owner: owner,
            index: index,
            tabColor: entry.tabColor,
            condensed: condensed,
            collapsed: collapse.collapsed.contains(entry.id),
            palette: palette,
            inProject: inProject,
            onToggleCollapse: { collapse.toggle(entry.id) })
    }

    /// The terminal's own background, a shade deeper.
    private var sidebarBackground: some View {
        ZStack {
            config.backgroundColor.opacity(config.backgroundOpacity)
            Color.black.opacity(0.28)
        }
    }

    /// The sigil and wordmark, then the tools.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                LivingSigil(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("GHOSTTY·EXTREME")
                        .font(Extreme.font(11.5))
                        .kerning(2.2)
                        .foregroundColor(Extreme.gold)
                        .extremeGlint()
                    Text("Α Ι · ΣΥΣΤΗΜΑ")
                        .font(Extreme.font(9))
                        .kerning(2.4)
                        .foregroundColor(Extreme.dim)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                NewSessionMenu(owner: owner, compact: true)
                Spacer(minLength: 0)
                EditorHeaderButton(owner: owner)
                ExtremeIconButton(icon: condensed ? .expand : .condense,
                                  help: condensed ? "Expand view" : "Condense view") { condensed.toggle() }
                LocalhostHeaderButton()
                ReviewHeaderButton()
                ExtremeIconButton(icon: .chart, help: "Agent activity and usage graphs (⌃⌘A)", action: ActivityDashboard.toggle)
                MissionControlButton()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// A small action icon in the row's hover chip, lit on hover.
private struct ChipIcon: View {
    let icon: PixelIcon
    @State private var hovering = false

    var body: some View {
        PixelIconView(icon: icon, color: hovering ? Extreme.gold : Extreme.muted, pixel: 1.1)
            .frame(width: 24, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hovering ? Extreme.raised : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// The pane's "Review N" chip when its agent's work is waiting, otherwise `diff`. Watches the
/// inbox itself, so the chip appears the moment a review is ready.
private struct ReviewOrDiffChip<Diff: View>: View {
    let surface: Ghostty.SurfaceView?
    @ViewBuilder let diff: () -> Diff
    @ObservedObject private var inbox = ReviewInbox.shared

    var body: some View {
        if let surface, inbox.item(for: surface)?.stage == .ready {
            ReviewPaneChip(surface: surface)
        } else {
            diff()
        }
    }
}

/// Opens this tab's code editor; while it's open, the same button closes it.
private struct EditorHeaderButton: View {
    let owner: TerminalController
    @ObservedObject private var panel = EditorPanel.shared

    var body: some View {
        let open = panel.isVisible(owner)
        ExtremeIconButton(icon: open ? .close : .code,
                          help: open ? "Close the code editor (⌃⌘E)" : "Open the code editor: watch the agent live (⌃⌘E)",
                          active: open) {
            panel.toggle(from: owner)
        }
        .disabled(HermesSessions.shared.isHermes(owner))
    }
}

/// Opens Mission Control (⌃⌘M); a dot shows when an agent is waiting.
private struct MissionControlButton: View {
    var body: some View {
        ExtremeIconButton(icon: .grid, help: "Mission Control (⌃⌘M)", action: MissionControl.toggle)
    }
}

// MARK: - Icon with status

/// A pane's icon: the agent's logo on its brand-colored circle (or a neutral terminal
/// circle), with a status badge cut into the bottom-right corner. Proportions follow
/// Warp's `render_icon_with_status` (circle 76%, glyph 43%, badge 57% of the box).
struct VerticalTabAvatar: View {
    let agent: VerticalTabAgentKind?
    var mood: AgentMood = .idle
    let badge: VerticalTabBadge
    let palette: VerticalTabsPalette
    /// Extra highlight on the row behind the avatar, so the badge ring matches it.
    var rowHighlight: Double = 0
    var size: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MoodSprite(kind: agent, mood: mood, pixel: size >= 22 ? 2 : 1.5)
                .frame(width: size, height: size)
                .background(Extreme.ink.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Extreme.line, lineWidth: 1))
            switch badge {
            case .none:
                EmptyView()
            case .working:
                PixelSpinner(color: Extreme.core, pixel: size >= 22 ? 3 : 2.5)
                    .padding(2)
                    .background(Extreme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Extreme.core.opacity(0.4), lineWidth: 1))
                    .offset(x: 6, y: 6)
            default:
                // Waiting on you blinks fast; finished or failed stays lit.
                let urgent = badge == .permission || badge == .input || badge == .bell
                PixelDot(color: badge.color(palette), blinking: urgent, size: size >= 22 ? 7 : 5,
                         interval: urgent ? 0.3 : 0.5)
                    .padding(2)
                    .background(Extreme.ink)
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size, height: size)
        .help(badge.helpText)
    }
}

/// An agent's logo in its brand color, or the terminal glyph, for the label line.
private struct VerticalTabKindLabel: View {
    let agent: VerticalTabAgentInfo?
    let palette: VerticalTabsPalette

    var body: some View {
        HStack(spacing: 5) {
            if let agent {
                Text(agent.kind.displayName)
                    .foregroundColor(agent.kind == .claude ? Extreme.claude : Extreme.text.opacity(0.8))
                    .fixedSize()
                if agent.activity != .ready {
                    Text("·").fixedSize()
                    Text(agent.activity.label)
                        .foregroundColor(agent.activity.badge == .none
                            ? Extreme.muted : agent.activity.badge.color(palette))
                        .fixedSize()
                }
                if let detail = agent.detail {
                    Text("·").fixedSize()
                    Text(detail)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            } else {
                Text("Terminal")
            }
        }
        .font(Extreme.font(10.5))
        .foregroundColor(Extreme.muted)
        .lineLimit(1)
    }
}

// MARK: - Tab group

private struct VerticalTabGroup: View {
    let controller: TerminalController
    let owner: TerminalController
    let index: Int
    let tabColor: TerminalTabColor
    let condensed: Bool
    let collapsed: Bool
    let palette: VerticalTabsPalette
    /// Inside a project bracket, which already provides the side margin.
    var inProject = false
    let onToggleCollapse: () -> Void

    @State private var snapshot: VerticalTabSnapshot = .empty
    @ObservedObject private var pins = VerticalTabsPins.shared

    private var isSelected: Bool { controller === owner }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed {
                VStack(spacing: condensed ? 2 : 6) {
                    ForEach(snapshot.panes) { pane in
                        VerticalTabPaneRow(
                            pane: pane,
                            controller: controller,
                            tabTitle: snapshot.title,
                            tabColor: tabColor,
                            isSelected: isSelected && pane.isFocused,
                            condensed: condensed,
                            palette: palette)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .extremePanel(active: isSelected, fill: isSelected ? Extreme.panel : Color.clear)
        .overlay(alignment: .leading) { colorCard }
        .padding(.leading, inProject ? 0 : 8)
        .padding(.trailing, 8)
        .onAppear(perform: update)
        .onReceive(VerticalTabsTicker.shared.publisher) {
            // Every tab window carries a sidebar, but only the one on screen needs
            // to stay current; the others refresh when their tab is selected.
            guard owner.window?.occlusionState.contains(.visible) == true else { return }
            update()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if pins.isPinned(controller) {
                PixelIconView(icon: .pin, color: Extreme.bronze, pixel: 1)
            }
            Text(displayTitle)
                .font(Extreme.font(12, weight: .semibold))
                .foregroundColor(isSelected ? Extreme.gold : Extreme.text.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(snapshot.title)
            if snapshot.hasUnseen {
                PixelDot(color: Extreme.live, blinking: true, size: 6)
                    .help("Agent finished while you were away")
            }
            Spacer(minLength: 4)
            if snapshot.panes.count > 1 {
                Text("\(snapshot.panes.count) panes")
                    .font(Extreme.font(10))
                    .foregroundColor(Extreme.dim)
                    .fixedSize()
            }
            if index <= 9 {
                Text("⌘\(index)")
                    .font(Extreme.font(10, weight: .semibold))
                    .foregroundColor(Extreme.dim)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Extreme.raised))
                    .fixedSize()
            }
            Button(action: onToggleCollapse) {
                PixelIconView(icon: collapsed ? .chevronRight : .chevronDown, color: Extreme.muted, pixel: 1.25)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, collapsed ? 8 : 5)
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .contextMenu { contextMenu }
    }

    /// A custom tab title, or else the project folder the tab is in.
    private var displayTitle: String {
        if let override = controller.titleOverride, !override.isEmpty { return override }
        if let pwd = snapshot.representative?.pwd {
            return pwd == NSHomeDirectory() ? "Home" : ProjectPath.displayName(LocalhostProject(folder: pwd).root)
        }
        return Self.cleanTitle(snapshot.title)
    }

    /// A colored tab carries its color as a bar down its left edge.
    @ViewBuilder
    private var colorCard: some View {
        if let ns = tabColor.displayColor {
            Rectangle().fill(Color(nsColor: ns)).frame(width: 2).padding(.vertical, 1)
        }
    }

    /// Samples the tab and redraws only if something visible changed.
    private func update() {
        let next = VerticalTabSnapshot(controller: controller)
        if next != snapshot { snapshot = next }
    }

    private func select() {
        guard let window = controller.window else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Agents prefix titles with activity glyphs (e.g. "✳ "); drop them for the header.
    static func cleanTitle(_ title: String) -> String {
        let trimmed = title.drop { !$0.isLetter && !$0.isNumber && $0 != "~" && $0 != "/" }
        let result = String(trimmed).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Terminal" : result
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let project = VerticalTabsProjects.project(of: controller),
           UserDefaults.standard.verticalTabsUngroupedProjects.contains(project.id) {
            Button("Group \(ProjectPath.displayName(project.root)) Tabs Again") {
                VerticalTabsProjects.shared.regroup(project.id)
            }
            Divider()
        }
        Button("Rename Tab…") {
            select()
            controller.promptTabTitle()
        }
        if let window = controller.window as? TerminalWindow {
            Menu("Tab Color") {
                ForEach(TerminalTabColor.allCases, id: \.self) { color in
                    Button {
                        window.tabColor = color
                    } label: {
                        if tabColor == color {
                            Label(color.localizedName, systemImage: "checkmark")
                        } else {
                            Text(color.localizedName)
                        }
                    }
                }
            }
        }
        Divider()
        Button("Close Tab") { controller.closeTab(nil) }
    }
}

// MARK: - Pane row

private struct VerticalTabPaneRow: View {
    let pane: VerticalTabPaneSnapshot
    let controller: TerminalController
    let tabTitle: String
    let tabColor: TerminalTabColor
    let isSelected: Bool
    let condensed: Bool
    let palette: VerticalTabsPalette

    @ObservedObject private var git = VerticalTabsGit.shared
    @State private var trackedPwd: String?
    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @EnvironmentObject private var overlay: VerticalTabsOverlayState

    private var gitInfo: VerticalTabsGitInfo? { git.info(for: pane.pwd) }

    var body: some View {
        Group {
            if condensed { condensedBody } else { expandedBody }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, condensed ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Extreme.raised : (hovering ? Extreme.raised.opacity(0.6) : Color.clear)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Extreme.gold.opacity(0.35) : Color.clear, lineWidth: 1))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Extreme.gold).frame(width: 3).padding(.vertical, 8).offset(x: -1)
                    .shadow(color: Extreme.gold.opacity(0.6), radius: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if pane.badge == .working {
                PixelActivityBar(color: Extreme.core).padding(.horizontal, 10).padding(.bottom, 2)
            } else if pane.badge == .permission || pane.badge == .input {
                Capsule().fill(Extreme.warn).frame(height: 2).padding(.horizontal, 10).padding(.bottom, 2)
                    .shadow(color: Extreme.warn.opacity(0.6), radius: 3)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .overlay(alignment: .topTrailing) {
            if hovering || overlay.menu?.pane.id == pane.id { hoverChip.padding(.top, 4).padding(.trailing, 4) }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { frame = geometry.frame(in: .named(verticalTabsSpace)) }
                    .onChange(of: geometry.frame(in: .named(verticalTabsSpace))) { frame = $0 }
            })
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                overlay.hoverBegan(.init(pane: pane, tabTitle: tabTitle, frame: frame))
            } else {
                overlay.hoverEnded(pane.id)
            }
        }
        .onTapGesture(perform: focus)
        .onReceive(NotificationCenter.default.publisher(for: VerticalTabsTestSupport.showOverlay)) { _ in
            guard isSelected else { return }
            if VerticalTabsTestSupport.overlayMode == "menu" {
                overlay.menu = .init(
                    controller: controller, pane: pane, tabColor: tabColor,
                    anchor: CGRect(x: frame.maxX - 56, y: frame.minY + 4, width: 26, height: 26))
            } else {
                hovering = true
                overlay.hoverBegan(.init(pane: pane, tabTitle: tabTitle, frame: frame))
            }
        }
        .onAppear {
            trackedPwd = pane.pwd
            git.track(pane.pwd)
        }
        .onDisappear {
            git.untrack(trackedPwd)
            trackedPwd = nil
        }
        .onChange(of: pane.pwd) { newValue in
            git.untrack(trackedPwd)
            trackedPwd = newValue
            git.track(newValue)
        }
    }

    /// Warp's floating ⋮ / × controls shown on the hovered row.
    private var hoverChip: some View {
        HStack(spacing: 0) {
            chipButton(.code, help: "Open this folder in the code editor") {
                overlay.dismissAll()
                EditorPanel.shared.show(from: controller, folder: pane.pwd)
            }
            chipButton(.more, help: "More") {
                overlay.dismissAll()
                overlay.menu = .init(
                    controller: controller,
                    pane: pane,
                    tabColor: tabColor,
                    anchor: CGRect(x: frame.maxX - 56, y: frame.minY + 4, width: 26, height: 26))
            }
            chipButton(.close, help: controller.surfaceTree.count > 1 ? "Close Pane" : "Close Tab") {
                overlay.dismissAll()
                if controller.surfaceTree.count > 1, let surface = pane.surface {
                    controller.closeSurface(surface)
                } else {
                    controller.closeTab(nil)
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Extreme.ink))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Extreme.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
    }

    private func chipButton(_ icon: PixelIcon, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChipIcon(icon: icon)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var avatar: some View {
        VerticalTabAvatar(
            agent: pane.agent?.kind,
            mood: AgentMood(pane.agent),
            badge: pane.badge,
            palette: palette,
            rowHighlight: isSelected ? 0.09 : (hovering ? 0.05 : 0),
            size: condensed ? 18 : 22)
    }

    private var expandedBody: some View {
        HStack(alignment: .top, spacing: 9) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                locationLine
                primaryLine
                HStack(spacing: 6) {
                    VerticalTabKindLabel(agent: pane.agent, palette: palette)
                    Spacer(minLength: 4)
                    // A pending review already counts the changes.
                    ReviewOrDiffChip(surface: pane.surface) { diffChip }
                }
                if let agent = pane.agent, agent.activity != .ready { detailLine(agent) }
            }
        }
    }

    private var condensedBody: some View {
        HStack(spacing: 8) {
            avatar
            primaryLine
            Spacer(minLength: 4)
            diffChip
        }
    }

    /// How long the agent has been at it, and the last thing it did: "2m · Edit: cart.py".
    private func detailLine(_ agent: VerticalTabAgentInfo) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
            Text(Self.elapsed(since: agent.since))
            if let action = agent.lastAction, !action.isEmpty {
                Text("·")
                Text(action)
                    .font(Extreme.mono(10))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(Extreme.font(10))
        .foregroundColor(Extreme.dim)
        .lineLimit(1)
    }

    static func elapsed(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(max(1, seconds))s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }

    /// "~/project • ⎇ branch"
    private var locationLine: some View {
        HStack(spacing: 5) {
            Text(pane.pwd.map(Self.abbreviate) ?? "~")
                .lineLimit(1)
                .truncationMode(.head)
            if let gitInfo {
                PixelIconView(icon: .branch, color: Extreme.bronze, pixel: 1)
                Text(gitInfo.branch)
                    .foregroundColor(Extreme.bronze)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .font(Extreme.font(11.5))
        .foregroundColor(Extreme.text)
    }

    /// What the pane is doing: the agent's task, or the terminal's title/command.
    @ViewBuilder
    private var primaryLine: some View {
        if let agent = pane.agent {
            Text(agent.task ?? VerticalTabGroup.cleanTitle(pane.title))
                .font(Extreme.font(11))
                .foregroundColor(Extreme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(pane.title.isEmpty ? "Terminal" : pane.title)
                .font(Extreme.font(11))
                .foregroundColor(Extreme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var diffChip: some View {
        if let gitInfo, gitInfo.added > 0 || gitInfo.removed > 0 {
            HStack(spacing: 3) {
                if gitInfo.added > 0 { Text("+\(gitInfo.added)").foregroundColor(Extreme.live) }
                if gitInfo.removed > 0 { Text("-\(gitInfo.removed)").foregroundColor(Extreme.danger) }
            }
            .font(Extreme.mono(10.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Extreme.ink))
            .overlay(Capsule().strokeBorder(Extreme.line, lineWidth: 1))
            .fixedSize()
        }
    }

    private func focus() {
        guard let window = controller.window else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
        if let surface = pane.surface { Ghostty.moveFocus(to: surface) }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
#endif
