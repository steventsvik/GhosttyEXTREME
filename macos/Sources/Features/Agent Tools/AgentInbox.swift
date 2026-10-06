#if os(macOS)
import AppKit
import Combine
import GhosttyKit

/// Delivers messages to agents that are already running: a handoff, a reviewer's findings,
/// a failed command.
///
/// A message is typed in (as a paste, then Enter) only when the agent is between turns
/// and its empty input box is on screen (see `AgentInputBox`). Until then it waits; it's
/// never typed over something the user started writing, into a permission prompt, or while
/// the agent works. Waiting messages show on the agent's sidebar card, where they can be
/// sent now (once the box is ready) or dropped.
final class AgentInbox: ObservableObject {
    static let shared = AgentInbox()

    struct Delivery: Identifiable {
        enum State: Equatable {
            /// Waiting for the agent to finish its turn and show an empty input box.
            case waiting
            /// Waiting because the user has text in the agent's input box.
            case blockedByTypedText
            case sent(Date)
        }

        let id = UUID()
        weak var surface: Ghostty.SurfaceView?
        let text: String
        /// What it is, for the card: "Review from Codex", "Failed: npm test".
        let label: String
        let created = Date()
        var state: State = .waiting
    }

    @Published private(set) var deliveries: [UUID: Delivery] = [:]

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    /// Messages wait this long before they're dropped.
    private static let lifetime: TimeInterval = 30 * 60

    private init() {
        NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tryAll() }
            .store(in: &cancellables)
    }

    /// Whether `surface`'s agent can take a message right now.
    enum Readiness: Equatable {
        case ready
        case working
        case typed
        /// No input box on screen (a dialog, a menu, the shell).
        case noInputBox
        case noAgent
    }

    static func readiness(of surface: Ghostty.SurfaceView) -> Readiness {
        guard let info = VerticalTabsAgents.shared.info(for: surface), info.kind == .claude || info.kind == .codex else {
            return .noAgent
        }
        if info.activity == .working || info.activity == .needsPermission { return .working }
        switch AgentInputBox.parse(surface.cachedVisibleContents.get()) {
        case .empty: return .ready
        case .typed: return MainActor.assumeIsolated { AgentInputBox.isGreyedOut(surface) } ? .ready : .typed
        case nil: return .noInputBox
        }
    }

    /// Queues `text` for the agent in `surface` and sends it as soon as the agent is ready.
    @discardableResult
    func deliver(_ text: String, to surface: Ghostty.SurfaceView, label: String) -> UUID {
        let delivery = Delivery(surface: surface, text: text, label: label)
        deliveries[delivery.id] = delivery
        tryDeliver(delivery.id)
        updateTimer()
        return delivery.id
    }

    func cancel(_ id: UUID) {
        deliveries.removeValue(forKey: id)
        updateTimer()
    }

    /// Messages still waiting for this pane's agent.
    func waiting(for surface: Ghostty.SurfaceView) -> [Delivery] {
        deliveries.values
            .filter { $0.surface === surface && ($0.state == .waiting || $0.state == .blockedByTypedText) }
            .sorted { $0.created < $1.created }
    }

    // MARK: Sending

    private func tryAll() {
        for id in deliveries.keys { tryDeliver(id) }
        updateTimer()
    }

    private func tryDeliver(_ id: UUID) {
        guard var delivery = deliveries[id] else { return }
        guard let surface = delivery.surface else {
            deliveries.removeValue(forKey: id)
            return
        }
        switch delivery.state {
        case .sent(let at):
            // Kept a moment so the card can say "Sent"; then forgotten.
            if Date().timeIntervalSince(at) > 8 { deliveries.removeValue(forKey: id) }
            return
        case .waiting, .blockedByTypedText:
            break
        }
        if Date().timeIntervalSince(delivery.created) > Self.lifetime {
            deliveries.removeValue(forKey: id)
            return
        }
        // One message per agent at a time: the next waits for the agent's reply turn.
        let alreadySent = deliveries.values.contains {
            $0.surface === surface && { if case .sent(let at) = $0.state { return Date().timeIntervalSince(at) < 5 } else { return false } }($0)
        }
        guard !alreadySent else { return }
        let before = delivery.state
        switch Self.readiness(of: surface) {
        case .ready:
            // Always on the main thread (timer, notification and callers all run there).
            MainActor.assumeIsolated { Self.send(delivery.text, to: surface) }
            delivery.state = .sent(Date())
        case .typed:
            delivery.state = .blockedByTypedText
        case .working, .noInputBox, .noAgent:
            delivery.state = .waiting
        }
        // Only a real change is published (every sidebar card watches this).
        if delivery.state != before { deliveries[id] = delivery }
    }

    /// Pastes the message (bracketed paste, so newlines don't submit early), then presses Enter.
    @MainActor
    private static func send(_ text: String, to surface: Ghostty.SurfaceView) {
        guard let model = surface.surfaceModel else { return }
        model.sendText(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak surface] in
            MainActor.assumeIsolated {
                guard let model = surface?.surfaceModel else { return }
                model.sendKeyEvent(.init(key: .enter, action: .press, text: "\r"))
                model.sendKeyEvent(.init(key: .enter, action: .release))
            }
        }
    }

    /// Checks once a second while anything waits (the screen can change without an event).
    private func updateTimer() {
        let pending = !deliveries.isEmpty
        if pending, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tryAll() }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !pending {
            timer?.invalidate()
            timer = nil
        }
    }
}
extension AgentInputBox {
    /// Whether the text in the input box is drawn dim: a suggestion like Claude Code's
    /// "commit this" or a placeholder, which looks the same as typed text in plain text.
    /// Typing replaces it, so a message can go in.
    @MainActor
    static func isGreyedOut(_ surface: Ghostty.SurfaceView) -> Bool {
        guard let cSurface = surface.surface else { return false }
        // ❯ and > (Claude Code), › (Codex): the first one found on screen decides.
        for prompt: UInt32 in [0x276F, 0x203A, 0x3E] {
            switch ghostty_surface_prompt_text_style(cSurface, prompt) {
            case 1: return true
            case 2: return false
            default: continue
            }
        }
        return false
    }

}
#endif
