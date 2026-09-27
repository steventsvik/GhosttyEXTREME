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

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
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
                VStack(spacing: 4) {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, entry in
                        if let controller = entry.controller {
                            VerticalTabRow(
                                controller: controller,
                                index: index + 1,
                                isSelected: controller === owner)
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

// MARK: - Status

/// The aggregate state of a pane or tab, in priority order (highest first).
enum VerticalTabStatus: Int, Comparable {
    case idle
    case running
    case attention
    case error

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(surface: Ghostty.SurfaceView) {
        if surface.progressReport?.state == .error {
            self = .error
        } else if surface.bell {
            self = .attention
        } else if let state = surface.progressReport?.state,
                  state == .set || state == .indeterminate || state == .pause {
            self = .running
        } else {
            self = .idle
        }
    }

    var color: Color? {
        switch self {
        case .idle: return nil
        case .running: return .blue
        case .attention: return .orange
        case .error: return .red
        }
    }

    var helpText: String {
        switch self {
        case .idle: return ""
        case .running: return "Running"
        case .attention: return "Needs attention"
        case .error: return "Error"
        }
    }
}

private struct VerticalTabStatusIndicator: View {
    let status: VerticalTabStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                Circle().fill(Color.secondary.opacity(0.25))
            case .running:
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            case .attention, .error:
                Circle()
                    .fill(status.color ?? .clear)
                    .shadow(color: (status.color ?? .clear).opacity(0.6), radius: 3)
            }
        }
        .frame(width: 8, height: 8)
        .frame(width: 14, height: 14)
        .help(status.helpText)
    }
}

// MARK: - Tab Row

private struct VerticalTabRow: View {
    @ObservedObject var controller: TerminalController
    let index: Int
    let isSelected: Bool

    @State private var title: String = ""
    @State private var hovering = false

    private var surfaces: [Ghostty.SurfaceView] { Array(controller.surfaceTree) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Aggregate status needs to observe every pane, so it is its own view.
            VerticalTabHeader(
                controller: controller,
                surfaces: surfaces,
                title: title,
                index: index,
                isSelected: isSelected,
                hovering: hovering)

            if surfaces.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(surfaces) { surface in
                        VerticalTabPaneRow(surface: surface, controller: controller)
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
            if let color = tabColor {
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
        .onReceive(titlePublisher) { title = $0 }
    }

    private var tabColor: NSColor? {
        (controller.window as? TerminalWindow)?.tabColor.displayColor
    }

    private var titlePublisher: AnyPublisher<String, Never> {
        guard let window = controller.window else { return Just("").eraseToAnyPublisher() }
        return window.publisher(for: \.title).eraseToAnyPublisher()
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
                        if window.tabColor == color {
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

private struct VerticalTabHeader: View {
    let controller: TerminalController
    let surfaces: [Ghostty.SurfaceView]
    let title: String
    let index: Int
    let isSelected: Bool
    let hovering: Bool

    /// The pane whose folder and git info represent the tab.
    private var representative: Ghostty.SurfaceView? {
        controller.focusedSurface ?? surfaces.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VerticalTabAggregateStatus(surfaces: surfaces)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Terminal" : title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let representative {
                    VerticalTabMetadataObserver(surface: representative, title: title)
                }
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
    }
}

/// Observes a pane's folder and re-polls git periodically so branch switches and edits
/// made outside the shell still show up.
private struct VerticalTabMetadataObserver: View {
    @ObservedObject var surface: Ghostty.SurfaceView
    let title: String
    @ObservedObject private var git = VerticalTabsGit.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            VerticalTabMetadata(pwd: surface.pwd, title: title, git: git.info(for: surface.pwd))
        }
    }
}

/// Folder and git line under a tab title.
private struct VerticalTabMetadata: View {
    let pwd: String?
    let title: String
    let git: VerticalTabsGitInfo?

    var body: some View {
        HStack(spacing: 6) {
            // Shells commonly title the tab with the folder already; don't repeat it.
            if let pwd, Self.abbreviate(pwd) != title {
                Text(Self.abbreviate(pwd))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if let git {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(git.branch).lineLimit(1)
                }
                .layoutPriority(1)
                if git.added > 0 {
                    Text("+\(git.added)").foregroundColor(.green)
                }
                if git.removed > 0 {
                    Text("−\(git.removed)").foregroundColor(.red)
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundColor(.secondary)
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// Shows the highest-priority status among all panes in a tab.
private struct VerticalTabAggregateStatus: View {
    let surfaces: [Ghostty.SurfaceView]

    var body: some View {
        // Nest an observer per surface so any pane's change re-renders the indicator.
        VerticalTabStatusObserver(surfaces: surfaces[...], worst: .idle)
    }
}

private struct VerticalTabStatusObserver: View {
    let surfaces: ArraySlice<Ghostty.SurfaceView>
    let worst: VerticalTabStatus

    var body: some View {
        if let first = surfaces.first {
            VerticalTabStatusObserverStep(surface: first, rest: surfaces.dropFirst(), worst: worst)
        } else {
            VerticalTabStatusIndicator(status: worst)
        }
    }
}

private struct VerticalTabStatusObserverStep: View {
    @ObservedObject var surface: Ghostty.SurfaceView
    let rest: ArraySlice<Ghostty.SurfaceView>
    let worst: VerticalTabStatus

    var body: some View {
        VerticalTabStatusObserver(surfaces: rest, worst: max(worst, VerticalTabStatus(surface: surface)))
    }
}

// MARK: - Pane Row

private struct VerticalTabPaneRow: View {
    @ObservedObject var surface: Ghostty.SurfaceView
    let controller: TerminalController

    var body: some View {
        HStack(spacing: 5) {
            VerticalTabStatusIndicator(status: VerticalTabStatus(surface: surface))
                .scaleEffect(0.85)
            Text(surface.title.isEmpty ? "Terminal" : surface.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(controller.focusedSurface === surface ? .medium : .regular)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(controller.focusedSurface === surface ? .primary : .secondary)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let window = controller.window else { return }
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
            Ghostty.moveFocus(to: surface)
        }
    }
}
#endif
