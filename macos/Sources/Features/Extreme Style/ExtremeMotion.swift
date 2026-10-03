#if os(macOS)
import AppKit
import Combine
import SwiftUI

// Keeping the chrome's motion cheap.
//
// Two rules, because SwiftUI re-lays-out the whole sidebar on every animation frame:
// 1. Endless motion (pulsing dots, spinners, activity bars) runs as Core Animation on
//    layers, which the system compositor animates without waking the app.
// 2. Motion that has to be SwiftUI (pixel-art sprites, the living sigil, the wordmark
//    glint) only runs while its window is on screen: `extremeMotion` turns false for
//    background tabs, hidden and minimized windows, so they cost nothing.

// MARK: - Is this window on screen?

private struct ExtremeMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while the view's window isn't visible (a background tab, minimized, covered).
    var extremeMotion: Bool {
        get { self[ExtremeMotionKey.self] }
        set { self[ExtremeMotionKey.self] = newValue }
    }
}

/// Tracks whether a window is actually on screen.
final class WindowMotion: ObservableObject {
    @Published private(set) var active = true
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window
        observers.forEach(NotificationCenter.default.removeObserver)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                                          NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeMainNotification]
        observers = names.map { center.addObserver(forName: $0, object: window, queue: .main) { [weak self] _ in self?.update() } }
        update()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func update() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized && window.isVisible
        if visible != active { active = visible }
    }
}

// MARK: - Core Animation primitives

/// A layer-hosting view that doesn't clip its glow.
class MotionLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Animations are dropped when a layer leaves its window; put them back on return.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { restartAnimations() }
    }

    func restartAnimations() {}
}

private extension Color {
    var cg: CGColor { NSColor(self).cgColor }
}

/// A glowing dot that pulses (opacity 1 → 0.25) when `blinking`.
struct PulseDotLayer: NSViewRepresentable {
    let color: Color
    let blinking: Bool
    let size: CGFloat
    let interval: Double

    final class View: MotionLayerView {
        let dot = CALayer()
        var blinking = false
        var interval = 0.5

        override init(frame: NSRect) {
            super.init(frame: frame)
            dot.shadowOpacity = 0.85
            dot.shadowOffset = .zero
            layer?.addSublayer(dot)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.frame = bounds
            dot.cornerRadius = bounds.width / 2
            dot.shadowRadius = bounds.width * 0.6
            CATransaction.commit()
        }

        override func restartAnimations() {
            dot.removeAnimation(forKey: "pulse")
            guard blinking else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = interval
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(pulse, forKey: "pulse")
        }
    }

    func makeNSView(context: Context) -> View { View(frame: NSRect(x: 0, y: 0, width: size, height: size)) }

    func updateNSView(_ view: View, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.dot.backgroundColor = color.cg
        view.dot.shadowColor = color.cg
        CATransaction.commit()
        if view.blinking != blinking || view.interval != interval {
            view.blinking = blinking
            view.interval = interval
            view.restartAnimations()
        }
    }
}

/// A glowing arc turning: "working".
struct SpinnerLayer: NSViewRepresentable {
    let color: Color
    let diameter: CGFloat

    final class View: MotionLayerView {
        let spin = CALayer()
        let gradient = CAGradientLayer()
        let ring = CAShapeLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            ring.fillColor = nil
            ring.strokeColor = NSColor.white.cgColor
            ring.lineCap = .round
            ring.strokeStart = 0.12
            gradient.mask = ring
            spin.addSublayer(gradient)
            spin.shadowOpacity = 0.6
            spin.shadowRadius = 2
            spin.shadowOffset = .zero
            layer?.addSublayer(spin)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spin.frame = bounds
            gradient.frame = spin.bounds
            ring.frame = spin.bounds
            let line = max(1.4, bounds.width * 0.17)
            ring.lineWidth = line
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: line / 2, dy: line / 2), transform: nil)
            CATransaction.commit()
            if spin.animation(forKey: "spin") == nil { restartAnimations() }
        }

        override func restartAnimations() {
            spin.removeAnimation(forKey: "spin")
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = Double.pi * 2
            turn.duration = 0.85
            turn.repeatCount = .infinity
            spin.add(turn, forKey: "spin")
        }
    }

    func makeNSView(context: Context) -> View { View(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter)) }

    func updateNSView(_ view: View, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.gradient.colors = [NSColor(color).withAlphaComponent(0).cgColor, color.cg]
        view.spin.shadowColor = color.cg
        CATransaction.commit()
    }
}

/// A thin track with a light sweeping along it: an agent at work.
struct ActivityBarLayer: NSViewRepresentable {
    let color: Color

    final class View: MotionLayerView {
        let track = CALayer()
        let sweep = CAGradientLayer()
        private var width: CGFloat = 0

        override init(frame: NSRect) {
            super.init(frame: frame)
            layer?.masksToBounds = true
            sweep.startPoint = CGPoint(x: 0, y: 0.5)
            sweep.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(track)
            layer?.addSublayer(sweep)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.cornerRadius = bounds.height / 2
            track.frame = bounds
            sweep.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.35, height: bounds.height)
            sweep.position = CGPoint(x: -bounds.width, y: bounds.midY)
            CATransaction.commit()
            if bounds.width != width {
                width = bounds.width
                restartAnimations()
            }
        }

        override func restartAnimations() {
            sweep.removeAnimation(forKey: "sweep")
            guard bounds.width > 0 else { return }
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = -bounds.width * 0.175
            move.toValue = bounds.width * 1.175
            move.duration = 1.3
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sweep.add(move, forKey: "sweep")
        }
    }

    func makeNSView(context: Context) -> View { View(frame: .zero) }

    func updateNSView(_ view: View, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.track.backgroundColor = NSColor(color).withAlphaComponent(0.12).cgColor
        let solid = NSColor(color)
        view.sweep.colors = [solid.withAlphaComponent(0).cgColor, solid.cgColor, solid.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }
}

// MARK: - Sparse timelines

/// Ticks only for a short burst (`steps` frames across `burst` seconds) once every
/// `every` seconds, instead of continuously: for effects that move briefly then rest.
struct BurstSchedule: TimelineSchedule {
    let every: TimeInterval
    let burst: TimeInterval
    let steps: Int

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let start = startDate.timeIntervalSinceReferenceDate
        var cycle = (start / every).rounded(.down)
        var step = 0
        return AnyIterator {
            while true {
                if step > steps { step = 0; cycle += 1 }
                let date = cycle * every + burst * Double(step) / Double(steps)
                step += 1
                if date >= start - 0.001 { return Date(timeIntervalSinceReferenceDate: date) }
            }
        }
    }
}
#endif
