#if os(macOS)
import AppKit
import CoreText
import SwiftUI

/// GhosttyEXTREME's look: near-black, bronze hairlines, gold for what matters, and one
/// pale cyan glow reserved for the AI itself. Everything is set in the terminal's own
/// monospace, panels are square with small corner ticks, and motion is stepped, like pixel
/// art, never smooth.
enum Extreme {
    // MARK: Palette

    static let ink = Color(rgb: 0x0B0A09)
    static let panel = Color(rgb: 0x100E0C)
    static let raised = Color(rgb: 0x17140F)
    /// Hairlines between and around panels.
    static let line = Color(rgb: 0x2E271D)
    static let lineStrong = Color(rgb: 0x4A3C28)
    static let bronze = Color(rgb: 0x967446)
    static let gold = Color(rgb: 0xDEB86E)
    /// The AI core: only for agents, the sigil's heart, and live activity.
    static let core = Color(rgb: 0x78DCEB)
    static let text = Color(rgb: 0xD8CFBF)
    static let muted = Color(rgb: 0x8C8374)
    static let dim = Color(rgb: 0x5C554A)
    static let live = Color(rgb: 0x7FC98A)
    static let warn = Color(rgb: 0xD9A55B)
    static let danger = Color(rgb: 0xD0695E)
    static let claude = Color(rgb: 0xD97757)

    // MARK: Type

    static let fontFamily = "JetBrains Mono"

    /// The UI font: the terminal's JetBrains Mono, at any size.
    /// The interface font: the system's, for crisp, readable chrome.
    static func font(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// Code, paths, ports and commands: the terminal's JetBrains Mono.
    static func mono(_ size: CGFloat) -> Font {
        fontRegistered ? .custom(fontFamily, size: size) : .system(size: size, design: .monospaced)
    }

    /// The standard corner radius for panels and cards.
    static let radius: CGFloat = 10

    static func nsFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "JetBrainsMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private(set) static var fontRegistered = false

    /// Makes the bundled JetBrains Mono available to the app. Called once at launch.
    static func registerFonts() {
        guard !fontRegistered else { return }
        if NSFont(name: "JetBrainsMono-Regular", size: 12) != nil { fontRegistered = true; return }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("EditorWeb/fonts/JetBrainsMono-Regular.ttf") else { return }
        fontRegistered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            || NSFont(name: "JetBrainsMono-Regular", size: 12) != nil
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - Pixel bitmaps

/// Draws a small bitmap (one character per pixel, `.` is empty) crisply at any scale.
struct PixelBitmap: View {
    let rows: [String]
    let colors: [Character: Color]
    var pixel: CGFloat = 2

    var body: some View {
        let width = rows.map(\.count).max() ?? 0
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard char != ".", let color = colors[char] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)),
                                 with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(width) * pixel, height: CGFloat(rows.count) * pixel)
        .accessibilityHidden(true)
    }
}

// MARK: - The sigil

/// The GhosttyEXTREME sigil: alpha and iota ("AI" in Greek) fused into one mark, the
/// iota as the alpha's spine and its crossbar broken open around a glowing core, sealed in
/// a hexagonal cell.
struct ExtremeSigil: View {
    var size: CGFloat = 32
    /// The core glows, breathing in steps.
    var alive = true
    @Environment(\.extremeMotion) private var motion

    static let rows = [
        "...............gg...............",
        "..............bbbb..............",
        "............bb....bb............",
        "...........b........b...........",
        ".........bb...dddd...bb.........",
        "........b...ddggggdd...b........",
        "......bb..dd...bb...dd..bb......",
        "....bb..dd.....bb.....dd..bb....",
        "...g..dd.......bb.......dd..g...",
        "...b.d........gbbg........d.b...",
        "...b.d........bbbb........d.b...",
        "...b.d.......gbbbbg.......d.b...",
        "...b.d.......gbbbbg.......d.b...",
        "...b.d.......b.bb.b.......d.b...",
        "...b.d......gb.bb.bg......d.b...",
        "...b.d......b..bb..b......d.b...",
        "...b.d......b..cc..b......d.b...",
        "...b.d.....gb.cwwc.bg.....d.b...",
        "...b.d.....gggcwwcggg.....d.b...",
        "...b.d....gb...cc...bg....d.b...",
        "...b.d....gb...bb...bg....d.b...",
        "...b.d....b....bb....b....d.b...",
        "...b.d...gb....bb....bg...d.b...",
        "...g..dggggg...bb...gggggd..g...",
        "....bb..dd.....bb.....dd..bb....",
        "......bb..dd...bb...dd..bb......",
        "........bb..ddggggdd..bb........",
        "..........bb..dddd..bb..........",
        "............bb....bb............",
        "..............bbbb..............",
        "...............gg...............",
    ]

    static let colors: [Character: Color] = [
        "d": Extreme.lineStrong, "b": Extreme.bronze, "g": Extreme.gold,
        "c": Extreme.core, "w": Color(rgb: 0xEBFCFF),
    ]

    var body: some View {
        let pixel = size / 32
        ZStack {
            if alive && motion {
                TimelineView(.periodic(from: .now, by: 0.35)) { context in
                    // Four steps up, four down: the core breathes like a pixel sprite.
                    let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 8
                    let level = Double(step < 4 ? step : 7 - step) / 3
                    Circle()
                        .fill(Extreme.core.opacity(0.10 + level * 0.22))
                        .frame(width: size * 0.34, height: size * 0.34)
                        .blur(radius: size * 0.09)
                        .offset(y: size * 0.04)
                }
            }
            PixelBitmap(rows: Self.rows, colors: Self.colors, pixel: pixel)
        }
        .frame(width: size, height: size * 31 / 32)
    }
}

// MARK: - Agent sprites

/// Small pixel sprites for the agents, in the spirit of Claude Code's own critter.
struct AgentSprite: View {
    /// Where the sprite's eyes look (Claude's critter has eyes to move).
    enum Eyes { case center, left, right, closed }

    let kind: VerticalTabAgentKind?
    var pixel: CGFloat = 2
    var eyes: Eyes = .center

    private var claudeEyes: String {
        switch eyes {
        case .center: return "..okooooko.."
        case .left: return "..kooookoo.."
        case .right: return "..ookooook.."
        case .closed: return "..oooooooo.."
        }
    }

    var body: some View {
        switch kind {
        case .claude:
            PixelBitmap(rows: [
                "..oooooooo..",
                claudeEyes,
                "oooooooooooo",
                "oooooooooooo",
                "..oooooooo..",
                "..o.o..o.o..",
            ], colors: ["o": Extreme.claude, "k": Extreme.ink], pixel: pixel)
        case .codex:
            // Preserve the pixel frame/status badges, with a legible vector mark inside.
            VerticalTabAgentLogo(kind: .codex, tint: Extreme.text)
                .frame(width: pixel * 8, height: pixel * 8)
        case .hermes:
            PixelBitmap(rows: [
                "...ggg....",
                "..gyyyg...",
                "..gy.yg...",
                "...ggg....",
                ".gggggg...",
                "g.gggg.g..",
                "..g..g....",
            ], colors: ["g": Color(rgb: 0x9B7BEA), "y": Extreme.gold], pixel: pixel * 0.8)
        case .none:
            // A terminal: a prompt and a cursor.
            PixelBitmap(rows: [
                "o.......",
                ".o......",
                "..o.....",
                ".o......",
                "o...oooo",
            ], colors: ["o": Extreme.muted], pixel: pixel * 0.9)
        default:
            // Any other agent: a small construct with the AI's eye.
            PixelBitmap(rows: [
                "..oooooo..",
                ".o......o.",
                ".o.cc.c.o.",
                ".o......o.",
                "..oooooo..",
                "..o....o..",
            ], colors: ["o": kind?.brandColor ?? Extreme.muted, "c": Extreme.core], pixel: pixel * 0.8)
        }
    }
}

/// An agent's pixel sprite in a square cell, for lists and cards.
struct AgentBadge: View {
    let kind: VerticalTabAgentKind?
    var size: CGFloat = 24

    var body: some View {
        AgentSprite(kind: kind, pixel: size >= 24 ? 2 : 1.5)
            .frame(width: size, height: size)
            .background(Extreme.ink)
            .overlay(Rectangle().strokeBorder(Extreme.line, lineWidth: 1))
    }
}

// MARK: - Pixel icons

/// 9×9 pixel icons for the chrome.
enum PixelIcon: String {
    case plus, globe, inbox, grid, condense, expand, close, restart, stop, play, eye, chevronDown, chevronRight, pin, bolt, more, branch, chart, code,
         target, desktop, tablet, phone

    var rows: [String] {
        switch self {
        case .plus: return ["....o....", "....o....", "....o....", "....o....", "ooooooooo", "....o....", "....o....", "....o....", "....o...."]
        case .globe: return ["..ooooo..", ".o..o..o.", "o..o.o..o", "ooooooooo", "o..o.o..o", "ooooooooo", "o..o.o..o", ".o..o..o.", "..ooooo.."]
        case .inbox: return ["ooooooooo", "o.......o", "o.......o", "o.......o", "ooo...ooo", "o..ooo..o", "o.......o", "o.......o", "ooooooooo"]
        case .grid: return ["oooo.oooo", "o..o.o..o", "o..o.o..o", "oooo.oooo", ".........", "oooo.oooo", "o..o.o..o", "o..o.o..o", "oooo.oooo"]
        case .condense: return ["ooooooooo", ".........", ".........", "ooooooooo", ".........", ".........", "ooooooooo", ".........", "........."]
        case .expand: return ["ooooooooo", ".........", "ooooooooo", ".........", "ooooooooo", ".........", "ooooooooo", ".........", "ooooooooo"]
        case .close: return ["o.......o", ".o.....o.", "..o...o..", "...o.o...", "....o....", "...o.o...", "..o...o..", ".o.....o.", "o.......o"]
        case .restart: return ["..oooo.o.", ".o....oo.", "o....ooo.", "o........", "o.......o", "o.......o", ".o.....o.", "..ooooo..", "........."]
        case .stop: return [".........", ".ooooooo.", ".ooooooo.", ".ooooooo.", ".ooooooo.", ".ooooooo.", ".ooooooo.", ".ooooooo.", "........."]
        case .play: return [".o.......", ".oo......", ".ooo.....", ".oooo....", ".ooooo...", ".oooo....", ".ooo.....", ".oo......", ".o......."]
        case .eye: return [".........", "..ooooo..", ".o.....o.", "o..ooo..o", "o..ooo..o", ".o.....o.", "..ooooo..", ".........", "........."]
        case .chevronDown: return [".........", ".........", "o.......o", ".o.....o.", "..o...o..", "...o.o...", "....o....", ".........", "........."]
        case .chevronRight: return ["..o......", "...o.....", "....o....", ".....o...", "......o..", ".....o...", "....o....", "...o.....", "..o......"]
        case .pin: return ["...ooo...", "..ooooo..", "..ooooo..", "...ooo...", "ooooooooo", "....o....", "....o....", "....o....", "....o...."]
        case .chart: return [".......oo", ".......oo", "....oo.oo", "....oo.oo", ".oo.oo.oo", ".oo.oo.oo", ".oo.oo.oo", ".oo.oo.oo", "ooooooooo"]
        case .more: return [".........", ".........", ".........", ".........", "oo.oo.oo.", "oo.oo.oo.", ".........", ".........", "........."]
        case .branch: return [".o.......", ".o.....o.", ".o.....o.", ".o....o..", ".o...o...", ".o..o....", ".oo......", ".o.......", ".o......."]
        case .target: return ["....o....", "..ooooo..", ".o..o..o.", ".o.....o.", "ooo.o.ooo", ".o.....o.", ".o..o..o.", "..ooooo..", "....o...."]
        case .desktop: return ["ooooooooo", "o.......o", "o.......o", "o.......o", "o.......o", "ooooooooo", "....o....", "..ooooo..", "........."]
        case .tablet: return [".ooooooo.", ".o.....o.", ".o.....o.", ".o.....o.", ".o.....o.", ".o.....o.", ".o.....o.", ".o..o..o.", ".ooooooo."]
        case .phone: return ["..ooooo..", "..o...o..", "..o...o..", "..o...o..", "..o...o..", "..o...o..", "..o...o..", "..o.o.o..", "..ooooo.."]
        case .code: return [".....o...", ".....o...", "..o.o.o..", ".o..o..o.", "o...o...o", ".o..o..o.", "..o.o.o..", "...o.....", "...o....."]
        case .bolt: return ["....oo...", "...oo....", "..oo.....", ".ooooo...", "...oo....", "..oo.....", ".oo......", "oo.......", "........."]
        }
    }
}

extension PixelIcon {
    /// The system symbol drawn for this icon.
    var symbol: String {
        switch self {
        case .plus: return "plus"
        case .globe: return "globe"
        case .inbox: return "tray.full"
        case .grid: return "square.grid.2x2"
        case .condense: return "rectangle.compress.vertical"
        case .expand: return "rectangle.expand.vertical"
        case .close: return "xmark"
        case .restart: return "arrow.clockwise"
        case .stop: return "stop.fill"
        case .play: return "play.fill"
        case .eye: return "eye"
        case .chevronDown: return "chevron.down"
        case .chevronRight: return "chevron.right"
        case .pin: return "pin.fill"
        case .bolt: return "bolt.fill"
        case .more: return "ellipsis"
        case .branch: return "arrow.triangle.branch"
        case .chart: return "chart.bar.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .target: return "scope"
        case .desktop: return "desktopcomputer"
        case .tablet: return "ipad"
        case .phone: return "iphone"
        }
    }
}

/// An icon in the chrome. (Named for the pixel icons it replaced; `pixel` sets its size,
/// the icon being nine "pixels" square.)
struct PixelIconView: View {
    let icon: PixelIcon
    var color: Color = Extreme.text.opacity(0.8)
    var pixel: CGFloat = 1.5

    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: pixel * 7.2, weight: .semibold))
            .foregroundColor(color)
            .frame(width: pixel * 9, height: pixel * 9)
    }
}

// MARK: - Panels and labels

/// A panel: rounded, with a soft top light and a hairline border that glows gold when active.
struct ExtremePanel: ViewModifier {
    var active = false
    var fill: Color = Extreme.panel

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Extreme.radius, style: .continuous)
        // The shadow comes from the card's shape, not its contents: cast from the contents, it
        // had to be redrawn every frame anything inside moved (a sprite, a spinner, a bar).
        content
            .background(
                shape.fill(fill)
                    .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.035), .clear],
                                                       startPoint: .top, endPoint: .center)))
                    .shadow(color: active ? Extreme.gold.opacity(0.14) : .black.opacity(0.25), radius: active ? 10 : 3, y: active ? 0 : 1))
            .overlay(shape.strokeBorder(active ? Extreme.gold.opacity(0.55) : Extreme.line.opacity(0.9), lineWidth: 1))
    }
}

extension View {
    func extremePanel(active: Bool = false, fill: Color = Extreme.panel) -> some View {
        modifier(ExtremePanel(active: active, fill: fill))
    }
}

/// `LOCALHOST ─────` : an uppercase, letter-spaced section label with a trailing rule.
struct ExtremeSectionLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Extreme.font(10.5, weight: .semibold))
                .kerning(1.1)
                .foregroundColor(Extreme.muted)
                .fixedSize()
            Rectangle().fill(Extreme.line.opacity(0.7)).frame(height: 1)
            trailing()
        }
    }
}

/// A glowing status light that pulses softly when `blinking`. Drawn and animated by Core
/// Animation (see ExtremeMotion.swift), so a pulsing dot never wakes the app.
struct PixelDot: View {
    let color: Color
    var blinking = false
    var size: CGFloat = 6
    /// Seconds per pulse; urgent states pulse faster.
    var interval: Double = 0.5

    var body: some View {
        PulseDotLayer(color: color, blinking: blinking, size: size, interval: interval)
            .frame(width: size, height: size)
    }
}

/// A smooth spinner: a glowing arc turning, for "working". Core Animation.
struct PixelSpinner: View {
    var color: Color = Extreme.core
    /// Size, as in the pixel spinner it replaced (three "pixels" across).
    var pixel: CGFloat = 2.5

    var body: some View {
        SpinnerLayer(color: color, diameter: pixel * 3)
            .frame(width: pixel * 3, height: pixel * 3)
    }
}

/// A thin track with a light sweeping along it: an agent at work. Core Animation.
struct PixelActivityBar: View {
    var color: Color = Extreme.core
    var pixel: CGFloat = 2

    var body: some View {
        ActivityBarLayer(color: color)
            .frame(height: max(2, pixel))
    }
}

/// Buttons for the tool windows: rounded, a hairline border that lights on hover, gold
/// when prominent, and a small press-down.
struct ExtremeButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ExtremeButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct ExtremeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .font(Extreme.font(11.5, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(prominent ? Extreme.ink : (hovering ? Extreme.gold : Extreme.text.opacity(0.9)))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(shape.fill(prominent ? (hovering ? Extreme.gold : Extreme.gold.opacity(0.9)) : (hovering ? Extreme.raised : Extreme.panel)))
            .overlay(shape.strokeBorder(prominent ? Extreme.gold : (hovering ? Extreme.gold.opacity(0.45) : Extreme.line), lineWidth: 1))
            .shadow(color: prominent && hovering ? Extreme.gold.opacity(0.35) : .clear, radius: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(shape)
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .fixedSize()
    }
}

extension View {
    /// The tool-window look: ink background, dark controls, pixel buttons.
    func extremeWindow() -> some View {
        self
            .background(Extreme.ink)
            .buttonStyle(ExtremeButtonStyle())
            .tint(Extreme.gold)
            .environment(\.colorScheme, .dark)
            .onAppear { Extreme.registerFonts() }
    }
}

/// A tool window's title block: pixel icon, uppercase title and a subtitle.
struct ExtremeWindowTitle: View {
    let icon: PixelIcon?
    let title: String
    var subtitle: String = ""
    var sigil = false

    var body: some View {
        HStack(spacing: 12) {
            if sigil {
                ExtremeSigil(size: 30)
            } else if let icon {
                PixelIconView(icon: icon, color: Extreme.gold, pixel: 2)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Extreme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Extreme.line, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Extreme.font(16, weight: .semibold)).foregroundColor(Extreme.text)
                if !subtitle.isEmpty {
                    Text(subtitle).font(Extreme.font(11.5, weight: .regular)).foregroundColor(Extreme.muted)
                }
            }
        }
    }
}

/// A flat square button: pixel icon (and optional label), hairline border on hover.
struct ExtremeIconButton: View {
    let icon: PixelIcon
    var label: String?
    var help: String = ""
    var tint: Color = Extreme.gold
    var badge: Int = 0
    var badgeColor: Color = Extreme.live
    /// Lit up while the thing it opens is showing.
    var active: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let foreground = active ? Extreme.ink : hovering ? tint : Extreme.text.opacity(0.85)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                PixelIconView(icon: icon, color: foreground, pixel: 1.5)
                if let label {
                    Text(label).font(Extreme.font(11.5, weight: .semibold))
                        .foregroundColor(foreground)
                        .fixedSize()
                }
            }
            .padding(.horizontal, label == nil ? 0 : 10)
            .frame(minWidth: 30, minHeight: 28)
            .background(shape.fill(active ? tint.opacity(hovering ? 0.85 : 1) : hovering ? Extreme.raised : Extreme.panel))
            .overlay(shape.strokeBorder(active ? tint : hovering ? tint.opacity(0.55) : Extreme.line, lineWidth: 1))
            .shadow(color: active || hovering ? tint.opacity(active ? 0.35 : 0.2) : .clear, radius: 6)
            .scaleEffect(hovering && !active ? 1.04 : 1)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(Extreme.font(9, weight: .bold))
                        .foregroundColor(Extreme.ink)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(badgeColor))
                        .shadow(color: badgeColor.opacity(0.6), radius: 3)
                        .offset(x: 5, y: -5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hovering = inside } }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: badge)
        .help(help)
        // Its label never gets squeezed when the row is tight.
        .fixedSize()
    }
}
#endif
