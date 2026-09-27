#if os(macOS)
import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted whenever the set, order, or decoration of tabs may have changed.
    static let verticalTabsNeedRefresh = Notification.Name("com.steventsvik.ghostty-custom.verticalTabsNeedRefresh")
}

enum VerticalTabs {
    /// UserDefaults key backing the sidebar's visibility (shared by all windows).
    static let visibleKey = "VerticalTabsVisible"

    /// UserDefaults key backing the sidebar's width.
    static let widthKey = "VerticalTabsWidth"

    /// UserDefaults key for the one-line-per-pane "condensed" layout.
    static let condensedKey = "VerticalTabsCondensed"

    static let defaultWidth: Double = 290
    static let widthRange: ClosedRange<Double> = 180...420

    static func setNeedsRefresh() {
        NotificationCenter.default.post(name: .verticalTabsNeedRefresh, object: nil)
    }

    /// Horizontal space the sidebar occupies, including its divider.
    static var occupiedWidth: CGFloat {
        let stored = UserDefaults.standard.object(forKey: widthKey) as? Double ?? defaultWidth
        return CGFloat(min(max(stored, widthRange.lowerBound), widthRange.upperBound)) + 1
    }

    /// The window content size needed to give the terminal `size` with the sidebar beside it.
    static func contentSize(forTerminal size: NSSize) -> NSSize {
        guard UserDefaults.standard.verticalTabsVisible else { return size }
        return NSSize(width: size.width + occupiedWidth, height: size.height)
    }

    /// Width the sidebar currently takes from the window, or 0 when hidden. Ghostty
    /// stores this alongside the "last window frame" it uses to size new windows.
    static var currentSidebarWidth: Double {
        UserDefaults.standard.verticalTabsVisible ? Double(occupiedWidth) : 0
    }

    /// Converts a saved window width to one that gives the terminal the same size it had
    /// when saved, accounting for the sidebar being shown, hidden, or resized since.
    static func restoredWindowWidth(_ savedWidth: Double, savedSidebarWidth: Double) -> Double {
        savedWidth - savedSidebarWidth + currentSidebarWidth
    }

    /// Widens a newly created window so the sidebar is added beside the terminal
    /// rather than taking columns away from it.
    static func widenNewWindow(_ window: NSWindow) {
        guard UserDefaults.standard.verticalTabsVisible else { return }
        resize(window, by: occupiedWidth)
    }

    /// Grows (or shrinks) the window leftward so the terminal keeps its size and
    /// position on screen when the sidebar appears or disappears.
    static func resize(_ window: NSWindow, by delta: CGFloat) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        var frame = window.frame
        frame.size.width = max(frame.size.width + delta, window.minSize.width)
        frame.origin.x -= frame.size.width - window.frame.size.width
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.width > visible.width { frame.size.width = visible.width }
        }
        window.setFrame(frame, display: true)
    }
}

/// One entry in the sidebar. Holds the controller weakly so the sidebar never
/// keeps a closed tab alive.
struct VerticalTabEntry: Identifiable, Equatable {
    let id: ObjectIdentifier
    weak var controller: TerminalController?
    let tabColor: TerminalTabColor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.tabColor == rhs.tabColor
    }
}

/// The ordered list of tabs in the tab group of the window that owns this sidebar.
/// Each window has its own model, but they all derive from the same tab group so
/// every sidebar in a group shows the same list.
final class VerticalTabsModel: ObservableObject {
    @Published private(set) var tabs: [VerticalTabEntry] = []
    /// Whether the owning window is the visible tab of its group.
    @Published private(set) var isSelectedTab = true

    private weak var owner: TerminalController?
    private var cancellables: Set<AnyCancellable> = []

    /// Watches the native tab bar so it can be re-hidden the moment macOS shows it
    /// (it does so on its own whenever a tab is added).
    private var tabBarObservation: NSKeyValueObservation?
    private weak var observedTabGroup: NSWindowTabGroup?

    init(owner: TerminalController) {
        self.owner = owner

        let center = NotificationCenter.default
        Publishers.Merge3(
            center.publisher(for: .verticalTabsNeedRefresh),
            center.publisher(for: NSWindow.didBecomeKeyNotification),
            center.publisher(for: NSWindow.willCloseNotification))
            // Tab group membership settles a runloop tick after these events, and
            // bursts (e.g. closing several tabs) collapse into one refresh.
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        UserDefaults.standard.publisher(for: \.VerticalTabsVisible)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let owner, let window = owner.window else { return }

        let windows = window.tabGroup?.windows ?? [window]
        let newTabs = windows.compactMap { window -> VerticalTabEntry? in
            guard let controller = window.windowController as? TerminalController else { return nil }
            return VerticalTabEntry(
                id: ObjectIdentifier(controller),
                controller: controller,
                tabColor: (window as? TerminalWindow)?.tabColor ?? .none)
        }
        // Only publish real changes; refresh is triggered by many window events.
        if newTabs != tabs {
            tabs = newTabs
        }
        let selected = window.tabGroup.map { $0.selectedWindow === window } ?? true
        if selected != isSelectedTab { isSelectedTab = selected }

        syncNativeTabBar(window: window)
    }

    /// When the sidebar is showing, the horizontal native tab bar is redundant, so hide it.
    ///
    /// macOS refuses `toggleTabBar` while a window has more than one tab, so instead we
    /// hide the titlebar accessory that hosts the tab bar, which also gives its space
    /// back to the content. macOS may re-show or rebuild it when tabs change, so this is
    /// re-applied whenever the tab bar's visibility or the tab list changes.
    /// The "tabs" titlebar style draws tabs into the titlebar itself, so we leave it alone.
    private func syncNativeTabBar(window: NSWindow) {
        guard let tabGroup = window.tabGroup else { return }

        if observedTabGroup !== tabGroup {
            observedTabGroup = tabGroup
            tabBarObservation = tabGroup.observe(\.isTabBarVisible, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyTabBarPreference() }
            }
        }
        applyTabBarPreference()
    }

    private func applyTabBarPreference() {
        guard let owner, let window = owner.window else { return }
        guard owner.ghostty.config.macosTitlebarStyle != .tabs else { return }

        let hide = UserDefaults.standard.verticalTabsVisible
        for accessory in window.titlebarAccessoryViewControllers where Self.isTabBar(accessory) {
            if accessory.isHidden != hide { accessory.isHidden = hide }
        }
    }

    private static func isTabBar(_ accessory: NSTitlebarAccessoryViewController) -> Bool {
        let view = accessory.view
        return view.className.contains("NSTabBar") || view.firstDescendant(withClassName: "NSTabBar") != nil
    }
}

extension UserDefaults {
    /// KVO-observable accessor; the key path name must match `VerticalTabs.visibleKey`.
    @objc dynamic var VerticalTabsVisible: Bool {
        object(forKey: VerticalTabs.visibleKey) as? Bool ?? true
    }

    var verticalTabsVisible: Bool { VerticalTabsVisible }
}

// MARK: - Menu

/// Installs "Toggle Vertical Tabs" (⌃⌘S) in the View menu.
final class VerticalTabsMenu: NSObject {
    static let shared = VerticalTabsMenu()
    private var installed = false

    func installIfNeeded() {
        guard !installed, let mainMenu = NSApp.mainMenu else { return }
        guard let viewMenu = mainMenu.items.first(where: { $0.submenu?.title == "View" })?.submenu else { return }
        installed = true

        let item = NSMenuItem(
            title: "Toggle Vertical Tabs",
            action: #selector(toggle(_:)),
            keyEquivalent: "s")
        item.keyEquivalentModifierMask = [.control, .command]
        item.target = self
        viewMenu.insertItem(item, at: 0)
        EditorPanel.installMenuItem(in: viewMenu, at: 1)
        viewMenu.insertItem(.separator(), at: 2)
    }

    @objc func toggle(_ sender: Any?) {
        let defaults = UserDefaults.standard
        let show = !defaults.verticalTabsVisible
        let delta = show ? VerticalTabs.occupiedWidth : -VerticalTabs.occupiedWidth

        // One resize per window or tab group (tabs in a group share a frame).
        var seenGroups: Set<ObjectIdentifier> = []
        for window in NSApp.windows where window.windowController is TerminalController && window.isVisible {
            if let group = window.tabGroup {
                guard seenGroups.insert(ObjectIdentifier(group)).inserted else { continue }
            }
            VerticalTabs.resize(window, by: delta)
        }

        defaults.set(show, forKey: VerticalTabs.visibleKey)
    }
}

extension VerticalTabsMenu: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = UserDefaults.standard.verticalTabsVisible ? .on : .off
        return true
    }
}
#endif
