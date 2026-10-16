#if os(macOS)
import Foundation

/// The designs Tellurion ships: each a terminal theme, an accent and an AI color, and a
/// window to match the vibe. The chrome follows the terminal's colors.
enum DesignTemplates {
    static let all: [TellurionDesign] = [
        TellurionDesign(
            id: "tellurion", name: "Tellurion", tagline: "Ink and bronze, gold for what matters, cyan for the AI",
            terminal: .custom(.tellurion), chrome: .fixed(.tellurion),
            window: WindowLook(opacity: 1, blur: 0, padding: 10, cursor: .block), builtIn: true),
        template("mocha", "Catppuccin Mocha", "Pastel night: soft lavender on a deep blue-black", theme: "Catppuccin Mocha",
                 accent: 0xCBA6F7, ai: 0x89DCEB, padding: 12),
        template("dracula", "Dracula", "The count's study: purple and pink on slate", theme: "Dracula",
                 accent: 0xBD93F9, ai: 0x8BE9FD, padding: 10),
        template("nord", "Nord", "Arctic: frost blues and a calm, even light", theme: "Nord",
                 accent: 0x88C0D0, ai: 0xB48EAD, padding: 12),
        template("gruvbox", "Gruvbox", "Retro warmth: amber and olive on brown paper, lit from behind", theme: "Gruvbox Dark",
                 accent: 0xFABD2F, ai: 0x8EC07C, padding: 10),
        template("tokyo", "Tokyo Night", "Neon city: electric blue on midnight", theme: "TokyoNight",
                 accent: 0x7AA2F7, ai: 0x7DCFFF, padding: 12),
        template("rosepine", "Rosé Pine", "Soho velvet: rose and foam on a dark plum", theme: "Rose Pine",
                 accent: 0xEBBCBA, ai: 0x9CCFD8, padding: 12),
        template("kanagawa", "Kanagawa", "Ink wash: carp yellow and wave blue, after Hokusai", theme: "Kanagawa Wave",
                 accent: 0xE6C384, ai: 0x7E9CD8, padding: 12),
        template("everforest", "Everforest", "Forest floor: moss and sage, easy on the eyes for hours", theme: "Everforest Dark Hard",
                 accent: 0xA7C080, ai: 0x7FBBB3, padding: 12),
        template("solarized", "Solarized", "Lab notebook: the classic sixteen, tuned for long reads", theme: "iTerm2 Solarized Dark",
                 accent: 0xB58900, ai: 0x2AA198, padding: 10),
        template("synthwave", "Synthwave", "Outrun: hot pink and cyan, a little see-through", theme: "Synthwave",
                 accent: 0xFF7EDB, ai: 0x36F9F6, opacity: 0.9, blur: 24, padding: 14, cursor: .bar),
        template("matrix", "Matrix", "Operator: green phosphor, underline cursor, nothing else", theme: "Matrix",
                 accent: 0x5BFF5B, ai: 0x00FF41, padding: 8, cursor: .underline),
        template("cyberpunk", "Cyberpunk", "Night City: acid yellow and cyan on black", theme: "Cyberpunk",
                 accent: 0xFCEE0A, ai: 0x00F0FF, padding: 10, cursor: .bar),
        template("monokai", "Monokai Pro", "Editor classic: warm yellow and teal on charcoal", theme: "Monokai Pro",
                 accent: 0xFFD866, ai: 0x78DCE8, padding: 10),
        template("github", "GitHub Dark", "Pull request: the blues and greens you review code in", theme: "GitHub Dark",
                 accent: 0x58A6FF, ai: 0x3FB950, padding: 12),
        template("oxocarbon", "Oxocarbon", "Carbon: IBM's pink and teal on true black", theme: "Oxocarbon",
                 accent: 0xFF7EB6, ai: 0x3DDBD9, padding: 12),
        template("flexoki", "Flexoki", "Inky: a printer's palette on warm black", theme: "Flexoki Dark",
                 accent: 0xD0A215, ai: 0x3AA99F, padding: 12),
        template("latte", "Catppuccin Latte", "Morning latte: a light desk, mauve and sky accents", theme: "Catppuccin Latte",
                 accent: 0x8839EF, ai: 0x04A5E5, padding: 12),
        template("gruvbox-light", "Gruvbox Light", "Paper and ink: a light retro desk", theme: "Gruvbox Light",
                 accent: 0xB57614, ai: 0x427B58, padding: 10),
        template("dawn", "Rosé Pine Dawn", "Dawn: rose and pine on cream, light and quiet", theme: "Rose Pine Dawn",
                 accent: 0xD7827E, ai: 0x56949F, padding: 12),
    ]

    static func template(_ id: String, _ name: String, _ tagline: String, theme: String, accent: UInt32, ai: UInt32,
                         opacity: Double = 1, blur: Int = 0, padding: Int = 10, cursor: DesignCursorStyle = .block) -> TellurionDesign {
        TellurionDesign(id: id, name: name, tagline: tagline, terminal: .theme(theme),
                        chrome: .auto(accent: DesignColor(rgb: accent), ai: DesignColor(rgb: ai)),
                        window: WindowLook(opacity: opacity, blur: blur, padding: padding, cursor: cursor), builtIn: true)
    }

    static func named(_ id: String) -> TellurionDesign? { all.first { $0.id == id } }
}
#endif
