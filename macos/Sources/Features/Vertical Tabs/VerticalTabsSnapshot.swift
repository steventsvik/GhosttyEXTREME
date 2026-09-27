#if os(macOS)
import AppKit
import Combine

/// Drives sidebar updates by sampling instead of subscribing.
///
/// The sidebar never observes the terminal. Terminal output — even an agent rewriting
/// its title thousands of times a second — costs the sidebar nothing; instead the sidebar
/// samples a handful of values on a fixed clock and redraws only when something changed.
/// Worst-case cost is therefore bounded by the tick rate, not by terminal activity.
final class VerticalTabsTicker {
    static let shared = VerticalTabsTicker()

    let publisher = PassthroughSubject<Void, Never>()

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Faster while the app is frontmost, slower when it is merely visible.
    private let activeInterval: TimeInterval = 0.5
    private let inactiveInterval: TimeInterval = 2

    private init() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.schedule(interval: self?.activeInterval ?? 0.5)
                self?.tick()
            }
            .store(in: &cancellables)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.schedule(interval: self?.inactiveInterval ?? 2) }
            .store(in: &cancellables)
        // Switching tabs should show fresh state immediately, not on the next tick.
        center.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
        schedule(interval: NSApp.isActive ? activeInterval : inactiveInterval)
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        // Generous tolerance lets macOS coalesce our wakeups with others.
        timer.tolerance = interval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard UserDefaults.standard.verticalTabsVisible else { return }
        publisher.send()
    }
}

/// The aggregate state of a pane or tab, in priority order (highest first).
enum VerticalTabStatus: Int, Comparable {
    case idle
    case running
    case attention
    case error

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(surface: Ghostty.SurfaceView) {
        switch surface.progressReport?.state {
        case .error:
            self = .error
        case _ where surface.bell:
            self = .attention
        case .set, .indeterminate, .pause:
            self = .running
        default:
            self = .idle
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

/// What the sidebar shows for one pane, captured at a point in time.
struct VerticalTabPaneSnapshot: Equatable, Identifiable {
    let id: ObjectIdentifier
    let title: String
    let pwd: String?
    let status: VerticalTabStatus
    let isFocused: Bool

    /// Held weakly so a snapshot never keeps a closed pane alive.
    private let surfaceRef: Weak<Ghostty.SurfaceView>
    var surface: Ghostty.SurfaceView? { surfaceRef.value }

    init(surface: Ghostty.SurfaceView, isFocused: Bool) {
        self.id = ObjectIdentifier(surface)
        self.title = surface.title
        self.pwd = surface.pwd
        self.status = VerticalTabStatus(surface: surface)
        self.isFocused = isFocused
        self.surfaceRef = Weak(surface)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.pwd == rhs.pwd
            && lhs.status == rhs.status && lhs.isFocused == rhs.isFocused
    }
}

/// What the sidebar shows for one tab, captured at a point in time.
struct VerticalTabSnapshot: Equatable {
    let title: String
    let panes: [VerticalTabPaneSnapshot]

    static let empty = VerticalTabSnapshot(title: "", panes: [])

    init(title: String, panes: [VerticalTabPaneSnapshot]) {
        self.title = title
        self.panes = panes
    }

    init(controller: TerminalController) {
        let focused = controller.focusedSurface
        self.title = controller.window?.title ?? ""
        self.panes = controller.surfaceTree.map {
            VerticalTabPaneSnapshot(surface: $0, isFocused: $0 === focused)
        }
    }

    /// The pane whose folder represents the tab.
    var representative: VerticalTabPaneSnapshot? {
        panes.first(where: \.isFocused) ?? panes.first
    }

    var status: VerticalTabStatus {
        panes.map(\.status).max() ?? .idle
    }
}
#endif
