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
    @AppStorage(VerticalTabs.visibleKey) private var visible: Bool = true
    @AppStorage(VerticalTabs.widthKey) private var width: Double = VerticalTabs.defaultWidth
    private let content: Content

    init(controller: TerminalController, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.controller = controller
        self.ghostty = ghostty
        self._model = StateObject(wrappedValue: VerticalTabsModel(owner: controller))
        self.content = content()
    }

    var body: some View {
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
                // "Your app is live" when a localhost session starts listening.
                LocalhostToastLayer()
                // Branding: pixel corner brackets (a traveling light while an agent works)
                // and the sigil assembling when the tab opens.
                TerminalFrameOverlay(controller: controller)
                NewTabSplash()
            }
            // Each tab has its own editor.
            if editorPanel.isVisible(controller) {
                EditorPanelColumn(controller: controller)
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
                EditorPanel.shared.show(from: controller, folder: (file as NSString).deletingLastPathComponent)
                EditorPanel.shared.session(for: controller).webView.openFile(file, line: 20)
                // `GHOSTTY_EXTREME_TEST_EDITOR_JS`: script run in the editor once it's loaded.
                if let script = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_EDITOR_JS"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        EditorPanel.shared.session(for: controller).webView.evaluateJavaScript(script)
                    }
                }
            }
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
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, entry in
                        if let controller = entry.controller, !isLocalhost(entry) {
                            VerticalTabGroup(
                                controller: controller,
                                owner: owner,
                                index: index + 1,
                                tabColor: entry.tabColor,
                                condensed: condensed,
                                collapsed: collapse.collapsed.contains(entry.id),
                                palette: palette,
                                onToggleCollapse: { collapse.toggle(entry.id) })
                        }
                    }
                }
                .padding(.bottom, 10)
            }

            // Localhost sessions stay in view, whatever else is open.
            if !localhostTabs.isEmpty {
                Rectangle().fill(Extreme.line).frame(height: 1)
                LocalhostSidebarSection(entries: localhostTabs, owner: owner)
            }

            // Bottom left: live usage of the user's AI subscriptions.
            Rectangle().fill(Extreme.line).frame(height: 1)
            UsagePanel(palette: palette)
        }
        .background(sidebarBackground)
        .onAppear { Extreme.registerFonts() }
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
                ExtremeSigil(size: 26)
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
    let badge: VerticalTabBadge
    let palette: VerticalTabsPalette
    /// Extra highlight on the row behind the avatar, so the badge ring matches it.
    var rowHighlight: Double = 0
    var size: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AgentSprite(kind: agent, pixel: size >= 22 ? 2 : 1.5)
                .frame(width: size, height: size)
                .background(Extreme.ink.opacity(0.6))
                .overlay(Rectangle().strokeBorder(Extreme.line, lineWidth: 1))
            switch badge {
            case .none:
                EmptyView()
            case .working:
                PixelSpinner(color: Extreme.core, pixel: size >= 22 ? 3 : 2.5)
                    .padding(2)
                    .background(Extreme.ink)
                    .overlay(Rectangle().strokeBorder(Extreme.core.opacity(0.4), lineWidth: 1))
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
        .padding(.horizontal, 8)
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
            Text(Self.cleanTitle(snapshot.title).uppercased())
                .font(Extreme.font(10))
                .kerning(1.6)
                .foregroundColor(isSelected ? Extreme.gold : Extreme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            if snapshot.hasUnseen {
                PixelDot(color: Extreme.live, blinking: true, size: 6)
                    .help("Agent finished while you were away")
            }
            Spacer(minLength: 4)
            if index <= 9 {
                Text("⌘\(index)").font(Extreme.font(9.5)).foregroundColor(Extreme.dim)
            }
            Text(snapshot.panes.count == 1 ? "1 pane" : "\(snapshot.panes.count) panes")
                .font(Extreme.font(9.5))
                .foregroundColor(Extreme.dim)
                .fixedSize()
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
        .padding(.horizontal, 8)
        .padding(.vertical, condensed ? 5 : 7)
        .background(isSelected ? Extreme.raised : (hovering ? Extreme.raised.opacity(0.6) : Color.clear))
        .overlay(Rectangle().strokeBorder(isSelected ? Extreme.lineStrong : Color.clear, lineWidth: 1))
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Extreme.gold).frame(width: 2) }
        }
        .overlay(alignment: .bottom) {
            if pane.badge == .working {
                PixelActivityBar(color: Extreme.core).padding(.horizontal, 8).padding(.bottom, 2)
            } else if pane.badge == .permission || pane.badge == .input {
                Rectangle().fill(Extreme.warn).frame(height: 2).padding(.horizontal, 8).padding(.bottom, 1)
            }
        }
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
        .background(Extreme.ink)
        .overlay(Rectangle().strokeBorder(Extreme.lineStrong, lineWidth: 1))
    }

    private func chipButton(_ icon: PixelIcon, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PixelIconView(icon: icon, color: Extreme.muted, pixel: 1)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var avatar: some View {
        VerticalTabAvatar(
            agent: pane.agent?.kind,
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
                    if let surface = pane.surface, ReviewInbox.shared.item(for: surface)?.stage == .ready {
                        ReviewPaneChip(surface: surface)
                    } else {
                        diffChip
                    }
                }
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
            .font(Extreme.font(10.5))
            .overlay(Rectangle().strokeBorder(Extreme.line, lineWidth: 1).padding(-1))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Rectangle().fill(Extreme.ink))
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
