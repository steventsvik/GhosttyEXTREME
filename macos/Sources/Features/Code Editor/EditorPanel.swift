#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The code editor panels. Each terminal tab has its own editor — its own folder, open
/// files and Agent timeline, following only that tab's terminal — created the first time
/// it's opened in that tab.
final class EditorPanel: ObservableObject {
    static let shared = EditorPanel()

    static let widthKey = "EditorPanelWidth"
    static let defaultWidth: Double = 720

    /// Tabs whose editor is currently open.
    @Published private(set) var visibleTabs: Set<ObjectIdentifier> = []

    private var sessions: [ObjectIdentifier: EditorSession] = [:]
    private var themeJSON: String?
    private var followTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: .ghosttyConfigDidChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.themeJSON != nil else { return }
                self.loadTheme()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] note in
                guard let controller = (note.object as? NSWindow)?.windowController as? TerminalController else { return }
                self?.sessions[ObjectIdentifier(controller)]?.follow()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.followVisible() }
            .store(in: &cancellables)
    }

    func isVisible(_ controller: TerminalController) -> Bool {
        visibleTabs.contains(ObjectIdentifier(controller))
    }

    func session(for controller: TerminalController) -> EditorSession {
        let id = ObjectIdentifier(controller)
        if let session = sessions[id] { return session }
        let session = EditorSession(controller: controller)
        sessions[id] = session
        if let themeJSON {
            // Empty while the theme is still loading; loadTheme applies it to all sessions.
            if !themeJSON.isEmpty { session.webView.setTheme(themeJSON) }
        } else {
            loadTheme()
        }
        // The editor goes away with its tab.
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: controller.window)
            .sink { [weak self] _ in
                self?.sessions.removeValue(forKey: id)?.close()
                self?.visibleTabs.remove(id)
            }
            .store(in: &cancellables)
        return session
    }

    /// Opens this tab's editor, optionally on a specific folder.
    func show(from controller: TerminalController?, folder: String? = nil) {
        guard let controller, !HermesSessions.shared.isHermes(controller) else { return }
        let session = session(for: controller)
        session.show(folder: folder)
        let id = ObjectIdentifier(controller)
        if !visibleTabs.contains(id), let window = controller.window { session.widen(window) }
        visibleTabs.insert(id)
        startFollowing()
        DispatchQueue.main.async { session.webView.focusEditor() }
    }

    func hide(returningFocusTo controller: TerminalController?) {
        guard let controller else { return }
        let id = ObjectIdentifier(controller)
        sessions[id]?.hide()
        visibleTabs.remove(id)
        if let surface = controller.focusedSurface { Ghostty.moveFocus(to: surface) }
    }

    func toggle(from controller: TerminalController?) {
        guard let controller else { return }
        if isVisible(controller) { hide(returningFocusTo: controller) } else { show(from: controller) }
    }

    /// Keeps open editors on their own terminal's folder and agent. Only editors whose
    /// tab is on screen do any work.
    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.followVisible() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func followVisible() {
        if visibleTabs.isEmpty {
            followTimer?.invalidate()
            followTimer = nil
            return
        }
        for id in visibleTabs { sessions[id]?.followIfOnScreen() }
    }

    /// Terminal colors and font, shared by every editor.
    private func loadTheme() {
        themeJSON = themeJSON ?? ""
        EditorTheme.load { [weak self] json in
            guard let self else { return }
            self.themeJSON = json
            self.sessions.values.forEach { $0.webView.setTheme(json) }
        }
    }

    /// The terminal controller of the frontmost window, if any.
    static var frontController: TerminalController? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? TerminalController
    }
}

/// One tab's editor: a web view following that tab's terminal pane and its agent.
final class EditorSession {
    private weak var controller: TerminalController?
    let webView = EditorWebView()
    private let feed = AgentFeed()
    private var lastStatus: [String: String]?
    private var isVisible = false
    /// How much the window was widened for this editor, so hiding can undo it.
    private var widenedBy: CGFloat = 0

    init(controller: TerminalController) {
        self.controller = controller
        feed.onItems = { [weak self] items, reset in self?.webView.sendAgentItems(items, reset: reset) }
    }

    func show(folder: String?) {
        isVisible = true
        if let folder = folder ?? controller?.focusedSurface?.pwd { webView.openFolder(folder) }
        follow()
    }

    func hide() {
        isVisible = false
        feed.stop()
        lastStatus = nil
        if let window = controller?.window { narrow(window) }
    }

    func close() {
        feed.stop()
    }

    func followIfOnScreen() {
        guard let window = controller?.window, window.occlusionState.contains(.visible) else { return }
        follow()
    }

    /// Shows this tab's focused pane: its folder in the Explorer, its agent in the panel.
    func follow() {
        guard isVisible, let surface = controller?.focusedSurface else { return }
        if let pwd = surface.pwd, pwd != webView.currentFolder { webView.openFolder(pwd) }

        let info = VerticalTabsAgents.shared.info(for: surface)
        if let info, let path = info.transcriptPath { feed.follow(path: path, kind: info.kind) }
        var status: [String: String]?
        if let info {
            status = [
                "kind": info.kind.rawValue,
                "name": info.kind.displayName,
                "activity": info.activity.label,
                "badge": String(describing: info.activity.badge),
                "task": info.task ?? "",
                "detail": info.detail ?? "",
                "live": info.transcriptPath == nil ? "no" : "yes",
            ]
        }
        guard status != lastStatus else { return }
        lastStatus = status
        webView.sendAgentStatus(status)
    }

    /// Makes room for the panel when the screen has space. Tabs share their window's
    /// size, so this only happens for a window with a single tab.
    func widen(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), (window.tabGroup?.windows.count ?? 1) <= 1,
              let screen = window.screen ?? NSScreen.main else { return }
        let panel = CGFloat(UserDefaults.standard.object(forKey: EditorPanel.widthKey) as? Double ?? EditorPanel.defaultWidth) + 1
        let visible = screen.visibleFrame
        let extra = min(panel, visible.width - window.frame.width)
        guard extra > 0 else { return }
        var frame = window.frame
        frame.size.width += extra
        if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        window.setFrame(frame, display: true, animate: true)
        widenedBy = extra
    }

    private func narrow(_ window: NSWindow) {
        guard widenedBy > 0, !window.styleMask.contains(.fullScreen) else { widenedBy = 0; return }
        var frame = window.frame
        frame.size.width = max(frame.width - widenedBy, window.minSize.width)
        window.setFrame(frame, display: true, animate: true)
        widenedBy = 0
    }
}

/// A tab's editor as placed in its window's layout: a resize handle and its web view.
struct EditorPanelColumn: View {
    let controller: TerminalController
    @AppStorage(EditorPanel.widthKey) private var width: Double = EditorPanel.defaultWidth
    @State private var startWidth: Double?
    @State private var cursorPushed = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)
                .overlay(
                    Color.clear
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside, !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
                            else if !inside, cursorPushed { NSCursor.pop(); cursorPushed = false }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let start = startWidth ?? width
                                    startWidth = start
                                    width = min(max(start - value.translation.width, 320), 1600)
                                }
                                .onEnded { _ in startWidth = nil }))
            EditorWebViewHost(webView: EditorPanel.shared.session(for: controller).webView)
                .frame(width: width)
        }
    }
}

/// Hosts one tab's editor web view.
private struct EditorWebViewHost: NSViewRepresentable {
    let webView: EditorWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) { attach(to: container) }

    private func attach(to container: NSView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}

// MARK: - Menu

extension EditorPanel {
    /// Adds "Toggle Code Editor" (⌃⌘E) to the View menu.
    static func installMenuItem(in menu: NSMenu, at index: Int) {
        let item = NSMenuItem(title: "Toggle Code Editor", action: #selector(EditorMenuTarget.toggle(_:)), keyEquivalent: "e")
        item.keyEquivalentModifierMask = [.control, .command]
        item.target = EditorMenuTarget.shared
        menu.insertItem(item, at: index)
    }
}

final class EditorMenuTarget: NSObject, NSMenuItemValidation {
    static let shared = EditorMenuTarget()

    @objc func toggle(_ sender: Any?) {
        EditorPanel.shared.toggle(from: EditorPanel.frontController)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let controller = EditorPanel.frontController else { return false }
        menuItem.state = EditorPanel.shared.isVisible(controller) ? .on : .off
        // Hermes tabs show Hermes's own app; there's no terminal folder to edit.
        return !HermesSessions.shared.isHermes(controller)
    }
}
#endif
