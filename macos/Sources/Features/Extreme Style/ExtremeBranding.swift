#if os(macOS)
import AppKit
import Combine
import SwiftUI

// Branding motion around the terminal. All of it is drawn over the terminal without
// taking clicks or keystrokes, and it's stepped like pixel art rather than smooth.

// MARK: - Terminal frame

/// Pixel corner brackets around the terminal. While an agent in the tab works, a cyan light
/// travels around the edge; when one needs you, the corners blink amber.
struct TerminalFrameOverlay: View {
    let controller: TerminalController

    private enum Mode: Equatable { case idle, working, waiting }
    @State private var mode: Mode = .idle
    @Environment(\.extremeMotion) private var motion

    var body: some View {
        Group {
            switch mode {
            // Core Animation layers: the blink and the travelling light cost nothing per frame.
            case .idle:
                FrameLights(color: Extreme.bronze.opacity(0.55))
            case .waiting:
                FrameLights(color: Extreme.warn, length: 20, blink: motion)
            case .working:
                FrameLights(color: Extreme.core.opacity(0.8), comet: motion)
            }
        }
        .allowsHitTesting(false)
        .onReceive(VerticalTabsTicker.shared.publisher) { update() }
        .onReceive(NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)) { _ in update() }
        .onAppear(perform: update)
    }

    private func update() {
        let infos = controller.surfaceTree.compactMap { VerticalTabsAgents.shared.info(for: $0) }
        let next: Mode = infos.contains { $0.activity == .needsPermission || $0.activity == .needsInput } ? .waiting
            : infos.contains { $0.activity == .working } ? .working : .idle
        if next != mode { mode = next }
    }

    private func corners(color: Color, length: CGFloat = 14) -> some View {
        Canvas { context, size in
            let w = size.width, h = size.height, t: CGFloat = 2
            for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] {
                let ox = dx > 0 ? x : x - t, oy = dy > 0 ? y : y - t
                context.fill(Path(CGRect(x: dx > 0 ? ox : x - length, y: oy, width: length, height: t)), with: .color(color))
                context.fill(Path(CGRect(x: ox, y: dy > 0 ? oy : y - length, width: t, height: length)), with: .color(color))
            }
        }
    }

    /// A short run of pixels chasing around the edge, with a fading tail.
    private func comet(at date: Date) -> some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let perimeter = 2 * (w + h)
            guard perimeter > 0 else { return }
            let segment: CGFloat = 10
            // One lap every ~3.5s, moving in whole-segment steps.
            let head = CGFloat((date.timeIntervalSinceReferenceDate * Double(perimeter) / 3.5)
                .truncatingRemainder(dividingBy: Double(perimeter)))
            let snapped = (head / segment).rounded(.down) * segment
            for i in 0..<7 {
                let distance = (snapped - CGFloat(i) * segment + perimeter).truncatingRemainder(dividingBy: perimeter)
                let alpha = 1 - Double(i) / 7
                context.fill(Path(rect(along: distance, length: segment - 2, w: w, h: h)),
                             with: .color(Extreme.core.opacity(alpha)))
            }
        }
        .shadow(color: Extreme.core.opacity(0.7), radius: 4)
    }

    /// The small rectangle `distance` along the perimeter, clockwise from the top left.
    private func rect(along distance: CGFloat, length: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        let t: CGFloat = 2
        if distance < w { return CGRect(x: distance, y: 0, width: length, height: t) }
        if distance < w + h { return CGRect(x: w - t, y: distance - w, width: t, height: length) }
        if distance < 2 * w + h { return CGRect(x: w - (distance - w - h) - length, y: h - t, width: length, height: t) }
        return CGRect(x: 0, y: h - (distance - 2 * w - h) - length, width: t, height: length)
    }
}

// MARK: - New tab splash

/// When a tab opens, the sigil assembles pixel by pixel over the terminal with the
/// wordmark, then fades. About a second and a half; it never takes input.
struct NewTabSplash: View {
    @State private var start = Date()
    @State private var visible = true

    private static let duration: TimeInterval = 1.5
    /// The sigil's pixels in a fixed shuffled order, so they appear scattered.
    private static let order: [(x: Int, y: Int, c: Character)] = {
        var pixels: [(x: Int, y: Int, c: Character)] = []
        for (y, row) in ExtremeSigil.rows.enumerated() {
            for (x, c) in row.enumerated() where c != "." { pixels.append((x, y, c)) }
        }
        var generator = SeededGenerator(seed: 0xE7)
        pixels.shuffle(using: &generator)
        return pixels
    }()

    var body: some View {
        if visible {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                // The timeline can tick a moment before `start` is reset on appear.
                let t = max(0, context.date.timeIntervalSince(start))
                let build = min(1, t / 0.75)
                let fade = t > 1.05 ? max(0, 1 - (t - 1.05) / 0.45) : 1
                VStack(spacing: 12) {
                    Canvas { gc, _ in
                        let px: CGFloat = 3
                        let count = Int(Double(Self.order.count) * build)
                        for pixel in Self.order.prefix(count) {
                            gc.fill(Path(CGRect(x: CGFloat(pixel.x) * px, y: CGFloat(pixel.y) * px, width: px, height: px)),
                                    with: .color(ExtremeSigil.colors[pixel.c] ?? Extreme.bronze))
                        }
                    }
                    .frame(width: 96, height: 93)
                    .shadow(color: Extreme.core.opacity(build >= 1 ? 0.6 : 0), radius: 10)
                    Text(String("GHOSTTY·EXTREME".prefix(Int(15 * min(1, max(0, (t - 0.3) / 0.5))))))
                        .font(Extreme.font(12))
                        .kerning(3)
                        .foregroundColor(Extreme.gold)
                        .frame(height: 16)
                }
                .padding(28)
                .background(Extreme.ink.opacity(0.82))
                .overlay(Rectangle().strokeBorder(Extreme.line, lineWidth: 1))
                .opacity(fade)
            }
            .allowsHitTesting(false)
            .onAppear {
                start = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { visible = false }
            }
        }
    }
}

/// A small deterministic random generator (so the splash always assembles the same way).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Agent linked

/// When an agent starts in a pane: a cyan scan line sweeps down it and an
/// "AI LINKED" tag flashes in the corner.
struct AgentLinkSweep: View {
    let surfaceView: Ghostty.SurfaceView
    @State private var linkedAt: Date?
    @State private var kind: VerticalTabAgentKind?
    @State private var hadAgent = false

    var body: some View {
        GeometryReader { geometry in
            if let linkedAt {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = max(0, context.date.timeIntervalSince(linkedAt))
                    let sweep = min(1, t / 0.7)
                    // Step the band down in 16 moves, like a pixel scanline.
                    let y = (sweep * 16).rounded(.down) / 16 * geometry.size.height
                    let fade = t > 1.6 ? max(0, 1 - (t - 1.6) / 0.5) : 1
                    ZStack(alignment: .topLeading) {
                        if sweep < 1 {
                            Rectangle()
                                .fill(LinearGradient(colors: [Extreme.core.opacity(0), Extreme.core.opacity(0.22)],
                                                     startPoint: .top, endPoint: .bottom))
                                .frame(height: 36)
                                .overlay(alignment: .bottom) { Rectangle().fill(Extreme.core).frame(height: 2) }
                                .offset(y: y - 36)
                        }
                        HStack(spacing: 7) {
                            PixelDot(color: Extreme.core, blinking: true, size: 6, interval: 0.2)
                            Text("AI LINKED · \((kind?.displayName ?? "AGENT").uppercased())")
                                .font(Extreme.font(10.5)).kerning(1.8)
                                .foregroundColor(Extreme.core)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Extreme.ink.opacity(0.9))
                        .overlay(Rectangle().strokeBorder(Extreme.core.opacity(0.6), lineWidth: 1))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(10)
                    }
                    .opacity(fade)
                }
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: VerticalTabsAgents.didChange)) { note in
            guard (note.object as? Ghostty.SurfaceView) === surfaceView else { return }
            let info = VerticalTabsAgents.shared.info(for: surfaceView)
            let has = info != nil && info?.kind != .hermes
            if has && !hadAgent {
                kind = info?.kind
                linkedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { linkedAt = nil }
            }
            hadAgent = has
        }
    }
}

// MARK: - Wordmark glint

/// A slow shine that passes across text every so often, in steps.
struct GlintModifier: ViewModifier {
    var every: TimeInterval = 9
    @Environment(\.extremeMotion) private var motion

    func body(content: Content) -> some View {
        if motion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            glint(content)
        } else {
            content
        }
    }

    /// Wakes only for the sweep's 13 steps, then sleeps until the next one.
    private func glint(_ content: Content) -> some View {
        content.overlay(
            TimelineView(BurstSchedule(every: every, burst: 0.9, steps: 12)) { context in
                GeometryReader { geometry in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: every)
                    let progress = min(1, phase / 0.9)
                    let stepped = (progress * 12).rounded(.down) / 12
                    let x = -geometry.size.width * 0.3 + stepped * geometry.size.width * 1.6
                    Rectangle()
                        .fill(Color.white.opacity(progress < 1 ? 0.75 : 0))
                        .frame(width: 10)
                        .rotationEffect(.degrees(20))
                        .offset(x: x)
                }
            }
            .mask(content)
            .allowsHitTesting(false))
    }
}

extension View {
    func extremeGlint(every: TimeInterval = 9) -> some View { modifier(GlintModifier(every: every)) }
}
#endif
