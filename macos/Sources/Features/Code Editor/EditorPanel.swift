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
    private var hasWorkspace = false

    /// How much each window was widened to fit the panel, so hiding can undo it.
    private var widened: [ObjectIdentifier: CGFloat] = [:]

    /// Shows the panel, opening the folder of the given terminal pane if no folder is open yet.
    func show(from controller: TerminalController?, folder: String? = nil) {
        if let folder {
            webView.openFolder(folder)
            hasWorkspace = true
        } else if !hasWorkspace, let pwd = controller?.focusedSurface?.pwd {
            webView.openFolder(pwd)
            hasWorkspace = true
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
