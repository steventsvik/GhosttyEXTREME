#if os(macOS)
import AppKit

/// What a coding agent running in a pane is doing, as reported by its hooks.
enum VerticalTabAgentActivity: Equatable {
    case ready
    case working
    case needsPermission
    case needsInput
    case done
    case failed

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .working: return "Working"
        case .needsPermission: return "Needs permission"
        case .needsInput: return "Needs input"
        case .done: return "Done"
        case .failed: return "Error"
        }
    }

    var badge: VerticalTabBadge {
        switch self {
        case .ready: return .none
        case .working: return .working
        case .needsPermission: return .permission
        case .needsInput: return .input
        case .done: return .done
        case .failed: return .error
        }
    }
}

struct VerticalTabAgentInfo: Equatable {
    let kind: VerticalTabAgentKind
    var activity: VerticalTabAgentActivity
    /// The prompt the agent is working on.
    var task: String?
    /// What it's blocked on: the tool awaiting permission, or the question asked.
    var detail: String?
    /// A finished or blocked agent the user hasn't looked at yet.
    var unseen: Bool
}

/// Receives agent status events and remembers the latest state per pane.
///
/// Events arrive as OSC 777 notifications titled `ghostty-custom://agent` with a small
/// JSON body, emitted by the agents' hooks (see `agent-hooks/` in the repo root). The
/// core forwards these without rate limiting; we consume them here so they never
/// become desktop notifications.
final class VerticalTabsAgents {
    static let shared = VerticalTabsAgents()

    static let titlePrefix = "ghostty-custom://"
    static let agentTitle = "ghostty-custom://agent"

    private final class Box {
        var info: VerticalTabAgentInfo
        init(_ info: VerticalTabAgentInfo) { self.info = info }
    }

    /// Weak keys: a closed pane's agent state disappears with it.
    private let states = NSMapTable<Ghostty.SurfaceView, Box>.weakToStrongObjects()

    private struct Event: Decodable {
        let agent: String?
        let event: String
        let detail: String?
    }

    func info(for surface: Ghostty.SurfaceView) -> VerticalTabAgentInfo? {
        states.object(forKey: surface)?.info
    }

    /// Clears the "unseen" flag once the user is looking at the pane.
    func markSeen(_ surface: Ghostty.SurfaceView) {
        guard let box = states.object(forKey: surface), box.info.unseen else { return }
        box.info.unseen = false
    }

    /// Returns true if the notification was an agent event (and so should not be shown).
    func handle(title: String, body: String, surface: Ghostty.SurfaceView) -> Bool {
        guard title.hasPrefix(Self.titlePrefix) else { return false }
        guard title == Self.agentTitle,
              let data = body.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data) else {
            // Unknown or malformed custom event: swallow it rather than show raw JSON.
            return true
        }
        apply(event, to: surface)
        VerticalTabsTicker.shared.tickNow()
        return true
    }

    private func apply(_ event: Event, to surface: Ghostty.SurfaceView) {
        if event.event == "session_end" {
            states.removeObject(forKey: surface)
            return
        }

        let activity: VerticalTabAgentActivity
        switch event.event {
        case "session_start": activity = .ready
        case "prompt_submit", "tool_complete": activity = .working
        case "permission_request": activity = .needsPermission
        case "input_needed": activity = .needsInput
        case "stop": activity = .done
        case "stop_failure": activity = .failed
        default: return
        }

        let existing = states.object(forKey: surface)?.info
        let kind = event.agent.map(VerticalTabAgentKind.init(id:)) ?? existing?.kind ?? .unknown
        let eventDetail = event.detail?.isEmpty == false ? event.detail : nil
        let task = event.event == "prompt_submit" ? eventDetail : existing?.task
        let detail = activity == .needsPermission || activity == .needsInput ? eventDetail : nil
        let needsEyes = activity != .working && activity != .ready
        let info = VerticalTabAgentInfo(
            kind: kind,
            activity: activity,
            task: task,
            detail: detail,
            unseen: needsEyes && !Self.isBeingViewed(surface))

        if let box = states.object(forKey: surface) {
            box.info = info
        } else {
            states.setObject(Box(info), forKey: surface)
        }
    }

    /// True when the pane is focused in the frontmost window of the active app.
    static func isBeingViewed(_ surface: Ghostty.SurfaceView) -> Bool {
        guard NSApp.isActive, let window = surface.window, window.isKeyWindow else { return false }
        return window.firstResponder === surface
    }
}
#endif
