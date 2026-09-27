#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// App-wide state of the code editor panel on the right side of terminal windows.
final class EditorPanel: ObservableObject {
    static let shared = EditorPanel()

    static let widthKey = "EditorPanelWidth"
    static let defaultWidth: Double = 720

    /// Starts closed each launch; the panel only exists once you open it.
    @Published private(set) var isVisible = false

    /// Created on first use: until then the editor costs nothing.
    private(set) lazy var webView = EditorWebView()

    /// How much each window was widened to fit the panel, so hiding can undo it.
    private var widened: [ObjectIdentifier: CGFloat] = [:]

    /// Keeps the Explorer on the active terminal's folder while the panel is open.
    private var followTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        NotificationCenter.default.publisher(for: .ghosttyConfigDidChange)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.themeApplied else { return }
                self.applyTerminalTheme()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] _ in self?.followTerminal() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.followTerminal() }
            .store(in: &cancellables)
    }

    private var themeApplied = false

    /// Tails the transcript of the agent in the followed terminal pane.
    private lazy var feed: AgentFeed = {
        let feed = AgentFeed()
        feed.onItems = { [weak self] items, reset in self?.webView.sendAgentItems(items, reset: reset) }
        return feed
    }()
    private var lastStatus: [String: String]?

    private func applyTerminalTheme() {
        themeApplied = true
        EditorTheme.load { [weak self] json in self?.webView.setTheme(json) }
    }

    /// Shows the folder of the focused pane in the frontmost terminal, following `cd`
    /// and tab switches the way the editor is expected to mirror the terminal.
    private func followTerminal() {
        guard isVisible, let surface = Self.frontController?.focusedSurface else { return }
        if let pwd = surface.pwd, pwd != webView.currentFolder { webView.openFolder(pwd) }
        followAgent(in: surface)
    }

    /// Shows the agent running in the followed pane: its live timeline and status.
    private func followAgent(in surface: Ghostty.SurfaceView) {
        let info = VerticalTabsAgents.shared.info(for: surface)
        if let info, let path = info.transcriptPath {
            feed.follow(path: path, kind: info.kind)
        }
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

    /// Shows the panel, opening the folder of the given terminal pane if no folder is open yet.
    func show(from controller: TerminalController?, folder: String? = nil) {
        if let folder = folder ?? controller?.focusedSurface?.pwd {
            webView.openFolder(folder)
        }
        if !themeApplied { applyTerminalTheme() }
        if followTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.followTerminal() }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            followTimer = timer
        }
        if !isVisible, let window = controller?.window { widen(window) }
        isVisible = true
        DispatchQueue.main.async { self.webView.focusEditor() }
    }

    /// Makes room for the panel beside the terminal when the screen has space, like the
    /// sidebar does, instead of squeezing the terminal.
    private func widen(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
        let panel = CGFloat(UserDefaults.standard.object(forKey: Self.widthKey) as? Double ?? Self.defaultWidth) + 1
        let visible = screen.visibleFrame
        let extra = min(panel, visible.width - window.frame.width)
        guard extra > 0 else { return }
        var frame = window.frame
        frame.size.width += extra
        if frame.maxX > visible.maxX { frame.origin.x = max(visible.minX, visible.maxX - frame.width) }
        window.setFrame(frame, display: true, animate: true)
        widened[ObjectIdentifier(window)] = extra
    }

    private func narrow(_ window: NSWindow) {
        guard let extra = widened.removeValue(forKey: ObjectIdentifier(window)),
              !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        frame.size.width = max(frame.width - extra, window.minSize.width)
        window.setFrame(frame, display: true, animate: true)
    }

    func hide(returningFocusTo controller: TerminalController?) {
        isVisible = false
        followTimer?.invalidate()
        followTimer = nil
        feed.stop()
        lastStatus = nil
        if let window = controller?.window { narrow(window) }
        if let surface = controller?.focusedSurface { Ghostty.moveFocus(to: surface) }
    }

    func toggle(from controller: TerminalController?) {
        if isVisible { hide(returningFocusTo: controller) } else { show(from: controller) }
    }

    /// The terminal controller of the frontmost window, if any.
    static var frontController: TerminalController? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? TerminalController
    }
}

/// The panel as placed in a window's layout: a resize handle and the shared web view.
struct EditorPanelColumn: View {
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
            EditorWebViewHost()
                .frame(width: width)
        }
    }
}

/// Hosts the app's single editor web view. Only the visible tab's window shows the
/// panel, so moving the view into whichever host appears is enough.
private struct EditorWebViewHost: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ view: HostView, context: Context) { view.attach() }

    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil else { return }
            let webView = EditorPanel.shared.webView
            guard webView.superview !== self else { return }
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
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
        menuItem.state = EditorPanel.shared.isVisible ? .on : .off
        return true
    }
}
#endif
