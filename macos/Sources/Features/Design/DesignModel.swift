#if os(macOS)
import AppKit
import GhosttyKit
import SwiftUI

// A design is everything about how Tellurion looks: the terminal's colors, the chrome
// around it (sidebar, panels, tool windows), the font, the window, and the logo. It is
// saved as JSON under ~/.ghostty-extreme and, for the terminal's part, written as a
// Ghostty config fragment that the main config includes.

// MARK: - Colors

/// A color as `#rrggbb`, so a design is plain text.
struct DesignColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = DesignColor(hex: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a #rrggbb color: \(text)"))
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var color: Color { Color(red: red, green: green, blue: blue) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Relative luminance, 0 (black) to 1 (white).
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    var isLight: Bool { luminance > 0.4 }

    /// This color moved `amount` of the way toward `other`.
    func mixed(with other: DesignColor, _ amount: Double) -> DesignColor {
        let t = min(1, max(0, amount))
        return DesignColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t, blue: blue + (other.blue - blue) * t)
    }

    /// WCAG contrast ratio against `other`.
    func contrast(with other: DesignColor) -> Double {
        let a = luminance + 0.05, b = other.luminance + 0.05
        return max(a, b) / min(a, b)
    }

    static let black = DesignColor(rgb: 0x000000)
    static let white = DesignColor(rgb: 0xFFFFFF)
}

// MARK: - The terminal

/// The terminal's own colors, in Ghostty's terms.
struct TerminalColors: Codable, Equatable {
    var background: DesignColor
    var foreground: DesignColor
    var cursor: DesignColor?
    var cursorText: DesignColor?
    var selectionBackground: DesignColor?
    var selectionForeground: DesignColor?
    /// The sixteen ANSI colors.
    var palette: [DesignColor]

    /// Tellurion's own: ink, parchment text and warm ANSI colors around the gold and cyan.
    static let tellurion = TerminalColors(
        background: DesignColor(rgb: 0x0B0A09), foreground: DesignColor(rgb: 0xD8CFBF),
        cursor: DesignColor(rgb: 0xDEB86E), cursorText: DesignColor(rgb: 0x0B0A09),
        selectionBackground: DesignColor(rgb: 0x2E271D), selectionForeground: DesignColor(rgb: 0xF2EAD8),
        palette: [0x17140F, 0xD0695E, 0x7FC98A, 0xDEB86E, 0x6FA4D8, 0xB98AD0, 0x78DCEB, 0xC9BFAE,
                  0x5C554A, 0xE07F73, 0x94D89C, 0xEFCB85, 0x8BB8E8, 0xC9A2E0, 0x96E6F2, 0xF2EAD8].map(DesignColor.init(rgb:)))

    /// The color at `index` (0–15), or the foreground when a palette is short.
    func ansi(_ index: Int) -> DesignColor {
        index < palette.count ? palette[index] : foreground
    }

    /// Reads the live configuration's colors: what the terminal shows right now.
    init?(config: Ghostty.Config) {
        guard let cfg = config.config else { return nil }
        func color(_ key: String) -> DesignColor? {
            var c = ghostty_config_color_s()
            guard ghostty_config_get(cfg, &c, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
            return DesignColor(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
        }
        var raw = ghostty_config_palette_s()
        let key = "palette"
        guard ghostty_config_get(cfg, &raw, key, UInt(key.lengthOfBytes(using: .utf8))) else { return nil }
        let palette: [DesignColor] = withUnsafeBytes(of: raw.colors) { bytes in
            let colors = bytes.bindMemory(to: ghostty_config_color_s.self)
            return (0..<16).map { DesignColor(red: Double(colors[$0].r) / 255, green: Double(colors[$0].g) / 255, blue: Double(colors[$0].b) / 255) }
        }
        let background = color("background") ?? DesignColor(Color(NSColor.windowBackgroundColor))
        let foreground = color("foreground") ?? DesignColor(Color(NSColor.textColor))
        self.init(background: background, foreground: foreground, cursor: color("cursor-color"), cursorText: color("cursor-text"),
                  selectionBackground: color("selection-background"), selectionForeground: color("selection-foreground"), palette: palette)
    }

    init(background: DesignColor, foreground: DesignColor, cursor: DesignColor? = nil, cursorText: DesignColor? = nil,
         selectionBackground: DesignColor? = nil, selectionForeground: DesignColor? = nil, palette: [DesignColor]) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.palette = palette
    }

    /// Parses a Ghostty theme file (`palette = 0=#…`, `background = #…`, …).
    init?(themeText text: String) {
        var palette = [DesignColor](repeating: .black, count: 16)
        var found = 0
        var values: [String: DesignColor] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "palette" {
                guard let inner = value.firstIndex(of: "="), let index = Int(value[..<inner].trimmingCharacters(in: .whitespaces)),
                      (0..<16).contains(index), let color = DesignColor(hex: String(value[value.index(after: inner)...])) else { continue }
                palette[index] = color
                found += 1
            } else if let color = DesignColor(hex: value) {
                values[key] = color
            }
        }
        guard found >= 16, let background = values["background"], let foreground = values["foreground"] else { return nil }
        self.init(background: background, foreground: foreground, cursor: values["cursor-color"], cursorText: values["cursor-text"],
                  selectionBackground: values["selection-background"], selectionForeground: values["selection-foreground"], palette: palette)
    }

    /// The Ghostty configuration lines for these colors.
    var configLines: [String] {
        var lines = ["background = \(background.hex)", "foreground = \(foreground.hex)"]
        if let cursor { lines.append("cursor-color = \(cursor.hex)") }
        if let cursorText { lines.append("cursor-text = \(cursorText.hex)") }
        if let selectionBackground { lines.append("selection-background = \(selectionBackground.hex)") }
        if let selectionForeground { lines.append("selection-foreground = \(selectionForeground.hex)") }
        for (index, color) in palette.prefix(16).enumerated() { lines.append("palette = \(index)=\(color.hex)") }
        return lines
    }
}

/// Where the terminal's colors come from.
enum TerminalColorSource: Codable, Equatable {
    /// Whatever the Ghostty config says: Tellurion leaves the terminal's colors alone.
    case mine
    /// One of Ghostty's built-in themes (or one in the user's themes folder), by name.
    case theme(String)
    /// Colors chosen in the Design window.
    case custom(TerminalColors)

    // Saved as `{"source": "theme", "theme": "Nord"}` rather than Swift's synthesized shape.
    private enum Keys: String, CodingKey { case source, theme, colors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .source) {
        case "theme": self = .theme(try c.decode(String.self, forKey: .theme))
        case "custom": self = .custom(try c.decode(TerminalColors.self, forKey: .colors))
        default: self = .mine
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .mine:
            try c.encode("mine", forKey: .source)
        case .theme(let name):
            try c.encode("theme", forKey: .source)
            try c.encode(name, forKey: .theme)
        case .custom(let colors):
            try c.encode("custom", forKey: .source)
            try c.encode(colors, forKey: .colors)
        }
    }
}

enum DesignCursorStyle: String, Codable, CaseIterable, Identifiable {
    case block, bar, underline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .block: return "Block"
        case .bar: return "Bar"
        case .underline: return "Underline"
        }
    }
}

/// The window around the terminal: opacity, blur, padding and the cursor. Nil leaves the
/// Ghostty config alone.
struct WindowLook: Codable, Equatable {
    var opacity: Double = 1
    /// Blur radius behind a translucent window; 0 is off.
    var blur: Int = 0
    var padding: Int = 8
    var cursor: DesignCursorStyle = .block
    var cursorBlink = true

    var configLines: [String] {
        var lines = ["background-opacity = \(String(format: "%.2f", opacity))"]
        lines.append("background-blur = \(opacity < 1 && blur > 0 ? String(blur) : "false")")
        lines.append("window-padding-x = \(padding)")
        lines.append("window-padding-y = \(padding)")
        lines.append("cursor-style = \(cursor.rawValue)")
        lines.append("cursor-style-blink = \(cursorBlink)")
        return lines
    }
}

/// The terminal's font. Nil fields leave the Ghostty config alone.
struct FontLook: Codable, Equatable {
    var family: String?
    var size: Double?

    var configLines: [String] {
        var lines: [String] = []
        if let family, !family.isEmpty {
            // The list is repeatable; an empty value resets it before ours is added.
            lines.append("font-family = ")
            lines.append("font-family = \"\(family.replacingOccurrences(of: "\"", with: ""))\"")
        }
        if let size { lines.append("font-size = \(String(format: "%g", size))") }
        return lines
    }
}

// MARK: - The chrome

/// The colors of everything Tellurion draws around the terminal.
struct ChromeColors: Codable, Equatable {
    var ink: DesignColor
    var panel: DesignColor
    var raised: DesignColor
    var line: DesignColor
    var lineStrong: DesignColor
    var bronze: DesignColor
    var gold: DesignColor
    var core: DesignColor
    var text: DesignColor
    var muted: DesignColor
    var dim: DesignColor
    var live: DesignColor
    var warn: DesignColor
    var danger: DesignColor

    /// Tellurion as shipped: near-black, bronze hairlines, gold for what matters, cyan for the AI.
    static let tellurion = ChromeColors(
        ink: DesignColor(rgb: 0x0B0A09), panel: DesignColor(rgb: 0x100E0C), raised: DesignColor(rgb: 0x17140F),
        line: DesignColor(rgb: 0x2E271D), lineStrong: DesignColor(rgb: 0x4A3C28),
        bronze: DesignColor(rgb: 0x967446), gold: DesignColor(rgb: 0xDEB86E), core: DesignColor(rgb: 0x78DCEB),
        text: DesignColor(rgb: 0xD8CFBF), muted: DesignColor(rgb: 0x8C8374), dim: DesignColor(rgb: 0x5C554A),
        live: DesignColor(rgb: 0x7FC98A), warn: DesignColor(rgb: 0xD9A55B), danger: DesignColor(rgb: 0xD0695E))

    var isLight: Bool { ink.isLight }

    /// Chrome colors that fit a terminal: its background becomes the ink, its foreground the
    /// text, and the panels, hairlines and muted text sit between the two. The accent (gold)
    /// and the AI color (core) come from the ANSI palette unless given.
    static func derived(from terminal: TerminalColors, accent: DesignColor? = nil, ai: DesignColor? = nil) -> ChromeColors {
        let bg = terminal.background, fg = terminal.foreground
        /// A palette color that reads against the background: the normal one, else its bright twin, else the foreground.
        func readable(_ normal: Int, _ bright: Int) -> DesignColor {
            let first = terminal.ansi(normal)
            if first.contrast(with: bg) >= 2.5 { return first }
            let second = terminal.ansi(bright)
            return second.contrast(with: bg) >= 2.5 ? second : fg
        }
        let gold = accent ?? readable(3, 11)
        let core = ai ?? readable(6, 14)
        return ChromeColors(
            ink: bg,
            panel: bg.mixed(with: fg, 0.035),
            raised: bg.mixed(with: fg, 0.075),
            line: bg.mixed(with: fg, 0.16),
            lineStrong: bg.mixed(with: fg, 0.28),
            bronze: gold.mixed(with: bg, 0.42),
            gold: gold,
            core: core,
            text: fg,
            muted: bg.mixed(with: fg, 0.58),
            dim: bg.mixed(with: fg, 0.40),
            live: readable(2, 10),
            warn: readable(3, 11),
            danger: readable(1, 9))
    }
}

/// How the chrome gets its colors.
enum ChromeSource: Codable, Equatable {
    /// Derived from the terminal's colors, with an optional accent and AI color.
    case auto(accent: DesignColor?, ai: DesignColor?)
    /// Every color chosen by hand.
    case fixed(ChromeColors)

    // Saved as `{"mode": "auto", "accent": "#…", "ai": "#…"}` or `{"mode": "fixed", "colors": {…}}`.
    private enum Keys: String, CodingKey { case mode, accent, ai, colors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .mode) {
        case "fixed": self = .fixed(try c.decode(ChromeColors.self, forKey: .colors))
        default: self = .auto(accent: try c.decodeIfPresent(DesignColor.self, forKey: .accent),
                              ai: try c.decodeIfPresent(DesignColor.self, forKey: .ai))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .auto(let accent, let ai):
            try c.encode("auto", forKey: .mode)
            try c.encodeIfPresent(accent, forKey: .accent)
            try c.encodeIfPresent(ai, forKey: .ai)
        case .fixed(let colors):
            try c.encode("fixed", forKey: .mode)
            try c.encode(colors, forKey: .colors)
        }
    }
}

// MARK: - The logo

/// The logo: a 32×32 pixel bitmap whose pixels are roles (gold, core, …) rather than
/// colors, so it recolors with the design.
struct DesignLogo: Codable, Equatable {
    static let size = 32

    /// One character per pixel; `.` is empty.
    var rows: [String]
    /// Also drawn as the Dock icon while Tellurion runs.
    var dockIcon = false

    enum Role: Character, CaseIterable, Identifiable {
        case gold = "g", bronze = "b", frame = "d", core = "c", bright = "w"
        case text = "t", muted = "m", live = "l", warn = "a", danger = "r", ink = "i"
        var id: Character { rawValue }
        var title: String {
            switch self {
            case .gold: return "Gold"
            case .bronze: return "Bronze"
            case .frame: return "Frame"
            case .core: return "AI"
            case .bright: return "Bright"
            case .text: return "Text"
            case .muted: return "Muted"
            case .live: return "Live"
            case .warn: return "Warn"
            case .danger: return "Danger"
            case .ink: return "Ink"
            }
        }
        func color(in chrome: ChromeColors) -> DesignColor {
            switch self {
            case .gold: return chrome.gold
            case .bronze: return chrome.bronze
            case .frame: return chrome.lineStrong
            case .core: return chrome.core
            case .bright: return chrome.core.mixed(with: .white, 0.8)
            case .text: return chrome.text
            case .muted: return chrome.muted
            case .live: return chrome.live
            case .warn: return chrome.warn
            case .danger: return chrome.danger
            case .ink: return chrome.ink
            }
        }
    }

    init(rows: [String], dockIcon: Bool = false) {
        self.rows = DesignLogo.normalized(rows)
        self.dockIcon = dockIcon
    }

    private enum CodingKeys: String, CodingKey { case rows, dockIcon }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rows: try container.decode([String].self, forKey: .rows),
                  dockIcon: try container.decodeIfPresent(Bool.self, forKey: .dockIcon) ?? false)
    }

    /// Exactly 32 rows of 32 characters.
    static func normalized(_ rows: [String]) -> [String] {
        (0..<size).map { y in
            let row = y < rows.count ? Array(rows[y]) : []
            return String((0..<size).map { x in x < row.count ? row[x] : "." })
        }
    }

    /// The pixel colors for `chrome`.
    func colors(in chrome: ChromeColors) -> [Character: Color] {
        Dictionary(uniqueKeysWithValues: Role.allCases.map { ($0.rawValue, $0.color(in: chrome).color) })
    }

    func pixel(_ x: Int, _ y: Int) -> Character {
        guard (0..<Self.size).contains(x), (0..<Self.size).contains(y) else { return "." }
        return Array(rows[y])[x]
    }

    mutating func set(_ x: Int, _ y: Int, to char: Character) {
        guard (0..<Self.size).contains(x), (0..<Self.size).contains(y) else { return }
        var row = Array(rows[y])
        row[x] = char
        rows[y] = String(row)
    }

    var isEmpty: Bool { rows.allSatisfy { $0.allSatisfy { $0 == "." } } }

    /// The Tellurion sigil: a T with a glowing core on its stem, sealed in a hexagonal cell.
    static let tellurion = DesignLogo(rows: [
        "...............gg...............",
        "..............bbbb..............",
        "............bb....bb............",
        "...........b........b...........",
        ".........bb...dddd...bb.........",
        "........b...dd....dd...b........",
        "......bb..dd........dd..bb......",
        "....bb..dd............dd..bb....",
        "...g..dd..g..........g..dd..g...",
        "...b.d....gggggggggggg....d.b...",
        "...b.d....bbbbbbbbbbbb....d.b...",
        "...b.d....g....bb....g....d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.........cc.........d.b...",
        "...b.d........cwwc........d.b...",
        "...b.d........cwwc........d.b...",
        "...b.d.........cc.........d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.........bb.........d.b...",
        "...b.d.......gggggg.......d.b...",
        "...g..d..................d..g...",
        "....bb..dd............dd..bb....",
        "......bb..dd........dd..bb......",
        "........bb..dd....dd..bb........",
        "..........bb..dddd..bb..........",
        "............bb....bb............",
        "..............bbbb..............",
        "...............gg...............",
    ])

    /// Just the cell, for drawing your own mark inside.
    static var cell: DesignLogo {
        var logo = tellurion
        for y in 8...23 { for x in 7...24 { logo.set(x, y, to: ".") } }
        return logo
    }

    static let blank = DesignLogo(rows: [])

    /// A shell prompt: a chevron and an underscore.
    static var prompt: DesignLogo {
        var logo = blank
        for i in 0..<8 {
            for t in 0..<3 {
                logo.set(7 + i, 8 + i + t, to: "g")
                logo.set(7 + i, 23 - i - t + 1, to: "g")
            }
        }
        for x in 17...26 { for y in 22...24 { logo.set(x, y, to: "c") } }
        return logo
    }

    /// A lightning bolt.
    static var bolt: DesignLogo {
        var logo = blank
        let shape = [
            "..........gggggg....",
            ".........gggggg.....",
            "........gggggg......",
            ".......gggggg.......",
            "......gggggg........",
            ".....gggggggggggg...",
            "....gggggggggggg....",
            "........cccccc......",
            ".......cccccc.......",
            "......cccccc........",
            ".....cccccc.........",
            "....cccccc..........",
            "...cccccc...........",
            "..cccccc............",
        ]
        for (dy, row) in shape.enumerated() { for (dx, ch) in row.enumerated() where ch != "." { logo.set(6 + dx, 9 + dy, to: ch) } }
        return logo
    }

    static let starters: [(title: String, logo: DesignLogo)] = [
        ("Tellurion", .tellurion), ("Empty cell", .cell), ("Prompt", .prompt), ("Bolt", .bolt), ("Blank", .blank),
    ]
}

// MARK: - A design

struct TellurionDesign: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// One line on its card: the vibe.
    var tagline: String = ""
    var terminal: TerminalColorSource = .mine
    var chrome: ChromeSource = .fixed(.tellurion)
    var font = FontLook()
    /// Nil leaves opacity, padding and the cursor to the Ghostty config.
    var window: WindowLook?
    var logo: DesignLogo = .tellurion
    /// True for the designs Tellurion ships; false for the user's own.
    var builtIn = false

    /// What a fresh install looks like: Tellurion's chrome around whatever the Ghostty config says.
    static let standard = TellurionDesign(id: "tellurion", name: "Tellurion", tagline: "As shipped: ink, bronze and gold around your own terminal colors",
                                          terminal: .mine, chrome: .fixed(.tellurion), builtIn: true)

    /// Whether this design is the one Tellurion ships with, ignoring the name.
    var isStandardLook: Bool {
        terminal == .mine && chrome == .fixed(.tellurion) && font == FontLook() && window == nil && logo == .tellurion
    }
}
#endif
