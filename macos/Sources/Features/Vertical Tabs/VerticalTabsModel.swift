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

    static let defaultWidth: Double = 240
    static let widthRange: ClosedRange<Double> = 180...420

    static func setNeedsRefresh() {
        NotificationCenter.default.post(name: .verticalTabsNeedRefresh, object: nil)
    }
}

/// One entry in the sidebar. Holds the controller weakly so the sidebar never
/// keeps a closed tab alive.
struct VerticalTabEntry: Identifiable {
    let id: ObjectIdentifier
    weak var controller: TerminalController?
}

/// The ordered list of tabs in the tab group of the window that owns this sidebar.
/// Each window has its own model, but they all derive from the same tab group so
/// every sidebar in a group shows the same list.
final class VerticalTabsModel: ObservableObject {
    @Published private(set) var tabs: [VerticalTabEntry] = []

    private weak var owner: TerminalController?
    private var cancellables: Set<AnyCancellable> = []

    init(owner: TerminalController) {
        self.owner = owner

        let center = NotificationCenter.default
        let refreshNames: [Notification.Name] = [
            .verticalTabsNeedRefresh,
            NSWindow.didBecomeKeyNotification,
            NSWindow.willCloseNotification,
        ]
        for name in refreshNames {
            center.publisher(for: name)
                // Tab group membership settles one runloop tick after these events.
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }

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
            return VerticalTabEntry(id: ObjectIdentifier(controller), controller: controller)
        }
        if newTabs.map(\.id) != tabs.map(\.id) {
            tabs = newTabs
        } else {
            // Same tabs, but decoration (color, selection) may have changed.
            objectWillChange.send()
        }

        syncNativeTabBar(window: window)
    }

    /// When the sidebar is showing, the horizontal native tab bar is redundant, so hide it.
    /// The "tabs" titlebar style draws tabs into the titlebar itself, so we leave it alone.
    private func syncNativeTabBar(window: NSWindow) {
        guard let owner, owner.window?.isKeyWindow == true else { return }
        guard owner.ghostty.config.macosTitlebarStyle != .tabs else { return }
        guard let tabGroup = window.tabGroup else { return }

        let sidebarVisible = UserDefaults.standard.verticalTabsVisible
        let wantsTabBar = !sidebarVisible && tabGroup.windows.count > 1
        if tabGroup.isTabBarVisible != wantsTabBar, tabGroup.windows.count > 1 || tabGroup.isTabBarVisible {
            window.toggleTabBar(nil)
        }
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
        viewMenu.insertItem(.separator(), at: 1)
    }

    @objc func toggle(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.verticalTabsVisible, forKey: VerticalTabs.visibleKey)
    }
}

extension VerticalTabsMenu: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = UserDefaults.standard.verticalTabsVisible ? .on : .off
        return true
    }
}
#endif
