#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// Places the vertical tabs sidebar to the left of the terminal content.
struct VerticalTabsLayout<Content: View>: View {
    let controller: TerminalController
    @ObservedObject var ghostty: Ghostty.App
    @StateObject private var model: VerticalTabsModel
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
                VerticalTabsResizeHandle(width: $width)
            }
            content
        }
        .onAppear { VerticalTabsMenu.shared.installIfNeeded() }
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

struct VerticalTabsSidebar: View {
    @ObservedObject var model: VerticalTabsModel
    let owner: TerminalController
    let config: Ghostty.Config

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, entry in
                        if let controller = entry.controller {
                            VerticalTabRow(
                                controller: controller,
                                owner: owner,
                                index: index + 1,
                                isSelected: controller === owner,
                                tabColor: entry.tabColor)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider().opacity(0.5)

            Button {
                owner.newTab(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Tab")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(sidebarBackground)
    }

    private var sidebarBackground: some View {
        ZStack {
            config.backgroundColor.opacity(config.backgroundOpacity)
            Color.primary.opacity(0.04)
        }
    }
}

// MARK: - Status Indicator

private struct VerticalTabStatusIndicator: View {
    let status: VerticalTabStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                Circle().fill(Color.secondary.opacity(0.25))
            case .running:
                // A static glyph rather than an animated spinner: an animation would
                // redraw the sidebar every frame for as long as a command runs.
                Image(systemName: "circle.dotted")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.blue)
            case .attention:
                Circle().fill(Color.orange)
            case .error:
                Circle().fill(Color.red)
            }
        }
        .frame(width: 8, height: 8)
        .frame(width: 14, height: 14)
        .help(status.helpText)
    }
}

// MARK: - Tab Row

private struct VerticalTabRow: View {
    let controller: TerminalController
    /// The controller whose window hosts this sidebar.
    let owner: TerminalController
    let index: Int
    let isSelected: Bool
    let tabColor: TerminalTabColor

    @State private var snapshot: VerticalTabSnapshot = .empty
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                VerticalTabStatusIndicator(status: snapshot.status)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title.isEmpty ? "Terminal" : snapshot.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    VerticalTabMetadata(pwd: snapshot.representative?.pwd, title: snapshot.title)
                }

                Spacer(minLength: 4)

                if hovering {
                    Button {
                        controller.closeTab(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                } else if index <= 9 {
                    Text("⌘\(index)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 1)
                }
            }

            if snapshot.panes.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.panes) { pane in
                        VerticalTabPaneRow(pane: pane, controller: controller)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.primary.opacity(0.12) : (hovering ? Color.primary.opacity(0.06) : .clear))
        )
        .overlay(alignment: .leading) {
            if let color = tabColor.displayColor {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: color))
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { select() }
        .contextMenu { contextMenu }
        .onAppear(perform: update)
        .onReceive(VerticalTabsTicker.shared.publisher) {
            // Every tab window carries a sidebar, but only the one on screen needs
            // to stay current; the others refresh when their tab is selected.
            guard owner.window?.occlusionState.contains(.visible) == true else { return }
            update()
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

/// Folder and git line under a tab title.
private struct VerticalTabMetadata: View {
    let pwd: String?
    let title: String
    @ObservedObject private var git = VerticalTabsGit.shared
    @State private var trackedPwd: String?

    var body: some View {
        let info = git.info(for: pwd)

        HStack(spacing: 6) {
            // Shells commonly title the tab with the folder already; don't repeat it.
            if let pwd, Self.abbreviate(pwd) != title {
                Text(Self.abbreviate(pwd))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if let info {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(info.branch).lineLimit(1)
                }
                .layoutPriority(1)
                if info.added > 0 {
                    Text("+\(info.added)").foregroundColor(.green)
                }
                if info.removed > 0 {
                    Text("−\(info.removed)").foregroundColor(.red)
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
        .onAppear {
            trackedPwd = pwd
            git.track(pwd)
        }
        .onDisappear {
            git.untrack(trackedPwd)
            trackedPwd = nil
        }
        .onChange(of: pwd) { newValue in
            git.untrack(trackedPwd)
            trackedPwd = newValue
            git.track(newValue)
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

// MARK: - Pane Row

private struct VerticalTabPaneRow: View {
    let pane: VerticalTabPaneSnapshot
    let controller: TerminalController

    var body: some View {
        HStack(spacing: 5) {
            VerticalTabStatusIndicator(status: pane.status)
                .scaleEffect(0.85)
            Text(pane.title.isEmpty ? "Terminal" : pane.title)
                .fontWeight(pane.isFocused ? .medium : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(pane.isFocused ? .primary : .secondary)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let window = controller.window, let surface = pane.surface else { return }
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
            Ghostty.moveFocus(to: surface)
        }
    }
}
#endif
