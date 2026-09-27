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
            }
            // Each tab has its own editor.
            if editorPanel.isVisible(controller) {
                EditorPanelColumn(controller: controller)
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
            VerticalTabsTestSupport.openTestTabsIfRequested(from: controller)
        }
    }
}

/// Test-only: `GHOSTTY_CUSTOM_TEST_TABS=N` (set by a test launch, never in normal use)
/// opens N tabs at startup so the sidebar can be exercised without UI scripting.
enum VerticalTabsTestSupport {
    private static var didOpen = false

    /// `GHOSTTY_CUSTOM_TEST_OVERLAY=hover|menu`: the selected row opens its hover card
    /// or ⋮ menu shortly after launch.
    static let overlayMode = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_OVERLAY"]
    static let showOverlay = Notification.Name("com.steventsvik.ghostty-custom.testShowOverlay")

    static func openTestTabsIfRequested(from controller: TerminalController) {
        guard !didOpen else { return }
        didOpen = true
        if overlayMode != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NotificationCenter.default.post(name: showOverlay, object: nil)
            }
        }
        if let name = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_COLOR"],
           let color = TerminalTabColor.allCases.first(where: { $0.localizedName.lowercased() == name }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { (controller.window as? TerminalWindow)?.tabColor = color }
        }
        if ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_SESSION"] == "hermes" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NewSessionKind.hermes.open(from: controller) }
        }
        if let file = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_EDITOR"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                EditorPanel.shared.show(from: controller, folder: (file as NSString).deletingLastPathComponent)
                EditorPanel.shared.session(for: controller).webView.openFile(file, line: 20)
            }
        }
        // Report which window is the visible tab so a test can capture that one.
        if let path = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_WINDOW_FILE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                let window = controller.window?.tabGroup?.selectedWindow ?? controller.window
                try? String(window?.windowNumber ?? 0).write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // `GHOSTTY_CUSTOM_TEST_RESELECT=1`: switch back to the first tab after 9s and
        // report its window in <window file>.2.
        if ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_RESELECT"] == "1",
           let path = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_WINDOW_FILE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                VerticalTabsActions.select(controller)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    try? String(controller.window?.windowNumber ?? 0).write(toFile: path + ".2", atomically: true, encoding: .utf8)
                }
            }
        }
        guard let value = ProcessInfo.processInfo.environment["GHOSTTY_CUSTOM_TEST_TABS"],
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
            .fill(Color.primary.opacity(0.1))
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

    var body: some View {
        let palette = VerticalTabsPalette(config: config)

        VStack(spacing: 0) {
            // Full labels when there's room, compact ones in a narrow sidebar.
            ViewThatFits(in: .horizontal) {
                headerButtons(compact: false)
                headerButtons(compact: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, entry in
                        if let controller = entry.controller {
                            VerticalTabGroup(
                                controller: controller,
                                owner: owner,
                                index: index + 1,
                                tabColor: entry.tabColor,
                                condensed: condensed,
                                collapsed: collapse.collapsed.contains(entry.id),
                                palette: palette,
                                onToggleCollapse: { collapse.toggle(entry.id) })
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                        }
                    }
                }
            }

            // Bottom left: live usage of the user's AI subscriptions.
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            UsagePanel(palette: palette)
        }
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        ZStack {
            config.backgroundColor.opacity(config.backgroundOpacity)
            Color.primary.opacity(0.04)
        }
    }

    private func headerButtons(compact: Bool) -> some View {
        HStack(spacing: 8) {
            VerticalTabsHeaderButton(
                symbol: condensed ? "list.bullet.below.rectangle" : "line.3.horizontal",
                title: compact ? (condensed ? "Expand" : "Condense") : (condensed ? "Expand view" : "Condense view")
            ) { condensed.toggle() }
            NewSessionMenu(owner: owner, compact: compact)
        }
    }
}

private struct VerticalTabsHeaderButton: View {
    let symbol: String
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                if let shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(hovering ? 0.08 : 0.03)))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
        ZStack(alignment: .topLeading) {
            circle
                .frame(width: size * 0.76, height: size * 0.76)

            if let symbol = badge.symbol {
                ZStack {
                    // Same layers as the sidebar background, so the ring reads as a cutout.
                    Circle().fill(palette.background)
                    Circle().fill(Color.primary.opacity(0.04 + rowHighlight))
                    Image(systemName: symbol)
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.bold)
                        .foregroundColor(badge.color(palette))
                        .frame(width: size * 0.3, height: size * 0.3)
                }
                .frame(width: size * 0.57, height: size * 0.57)
                .offset(x: size * 0.43, y: size * 0.43)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .help(badge.helpText)
    }

    @ViewBuilder
    private var circle: some View {
        if let agent {
            ZStack {
                Circle().fill(agent.brandColor)
                if agent.logoAsset != nil {
                    VerticalTabAgentLogo(kind: agent, tint: agent.glyphOnBrand)
                        .frame(width: size * (agent.logoIsTemplate ? 0.43 : 0.62),
                               height: size * (agent.logoIsTemplate ? 0.43 : 0.62))
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundColor(agent.glyphOnBrand)
                }
            }
        } else {
            ZStack {
                Circle().fill(Color.primary.opacity(0.12))
                Text(">_")
                    .font(.system(size: size * 0.3, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// An agent's logo in its brand color, or the terminal glyph, for the label line.
private struct VerticalTabKindLabel: View {
    let agent: VerticalTabAgentInfo?
    let palette: VerticalTabsPalette

    var body: some View {
        HStack(spacing: 5) {
            if let agent {
                VerticalTabAgentLogo(kind: agent.kind, tint: agent.kind.standaloneLogoColor)
                    .frame(width: 12, height: 12)
                Text(agent.kind.displayName)
                    .fixedSize()
                if agent.activity != .ready {
                    Text("·").fixedSize()
                    Text(agent.activity.label)
                        .foregroundColor(agent.activity.badge == .none
                            ? .secondary : agent.activity.badge.color(palette))
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
                Text(">_").font(.system(size: 10, weight: .bold, design: .monospaced))
                Text("Terminal")
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
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
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .background(colorCard)
        // Colored tabs sit as a card inset from the sidebar edges, like Warp.
        .padding(.horizontal, tabColor.displayColor == nil ? 0 : 6)
        .padding(.vertical, tabColor.displayColor == nil ? 0 : 5)
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
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(45))
            }
            Text(Self.cleanTitle(snapshot.title).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.4)
                .foregroundColor(isSelected ? .primary : (tabColor.displayColor == nil ? .secondary : .primary.opacity(0.85)))
                .lineLimit(1)
                .truncationMode(.tail)
            if snapshot.hasUnseen {
                Circle().fill(palette.green).frame(width: 6, height: 6)
                    .help("Agent finished while you were away")
            }
            Spacer(minLength: 4)
            if index <= 9 {
                Text("⌘\(index)").font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
            }
            Text(snapshot.panes.count == 1 ? "1 pane" : "\(snapshot.panes.count) panes")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.8))
                .fixedSize()
            Button(action: onToggleCollapse) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, collapsed ? 10 : 6)
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .contextMenu { contextMenu }
    }

    /// A colored tab is filled with a light, translucent tint of its color and outlined in
    /// it, so the whole tab reads as that color while its text stays legible.
    @ViewBuilder
    private var colorCard: some View {
        if let ns = tabColor.displayColor {
            // A softened, pastel version of the color, as Warp uses.
            let pastel = Color(nsColor: ns.usingColorSpace(.sRGB)?.blended(withFraction: 0.3, of: .white) ?? ns)
            RoundedRectangle(cornerRadius: 9)
                .fill(pastel.opacity(isSelected ? 0.55 : 0.44))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(pastel.opacity(isSelected ? 0.95 : 0.7), lineWidth: 1))
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
        .padding(.vertical, condensed ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isSelected ? 0.09 : (hovering ? 0.05 : 0))))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(isSelected ? 0.18 : 0), lineWidth: 1))
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
            chipButton("ellipsis", rotated: true, help: "More") {
                overlay.dismissAll()
                overlay.menu = .init(
                    controller: controller,
                    pane: pane,
                    tabColor: tabColor,
                    anchor: CGRect(x: frame.maxX - 56, y: frame.minY + 4, width: 26, height: 26))
            }
            chipButton("xmark", help: controller.surfaceTree.count > 1 ? "Close Pane" : "Close Tab") {
                overlay.dismissAll()
                if controller.surfaceTree.count > 1, let surface = pane.surface {
                    controller.closeSurface(surface)
                } else {
                    controller.closeTab(nil)
                }
            }
        }
        .padding(2)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(palette.background)
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.09))
            })
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func chipButton(_ symbol: String, rotated: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(rotated ? 90 : 0))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
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
                    diffChip
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
                Text("•").foregroundColor(.secondary)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(gitInfo.branch)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 12))
        .foregroundColor(.primary.opacity(0.9))
    }

    /// What the pane is doing: the agent's task, or the terminal's title/command.
    @ViewBuilder
    private var primaryLine: some View {
        if let agent = pane.agent {
            Text(agent.task ?? VerticalTabGroup.cleanTitle(pane.title))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(pane.title.isEmpty ? "Terminal" : pane.title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var diffChip: some View {
        if let gitInfo, gitInfo.added > 0 || gitInfo.removed > 0 {
            HStack(spacing: 3) {
                if gitInfo.added > 0 { Text("+\(gitInfo.added)").foregroundColor(palette.green) }
                if gitInfo.removed > 0 { Text("-\(gitInfo.removed)").foregroundColor(palette.red) }
            }
            .font(.system(size: 11).monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
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
