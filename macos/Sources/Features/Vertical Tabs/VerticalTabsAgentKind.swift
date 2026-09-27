#if os(macOS)
import SwiftUI

/// The coding agents the sidebar knows how to brand. Names, brand colors and logos
/// follow Warp's `CLIAgent` definitions (warpdotdev/warp, app/src/terminal/cli_agent.rs).
enum VerticalTabAgentKind: String, CaseIterable {
    case claude
    case codex
    case gemini
    case opencode
    case amp
    case copilot
    case cursor
    case droid
    case goose
    case hermes
    case unknown

    /// Resolves the `agent` field of an event ("claude", "codex", ...).
    init(id: String) {
        self = Self(rawValue: id.lowercased()) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .amp: return "Amp"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .droid: return "Droid"
        case .goose: return "Goose"
        case .hermes: return "Hermes"
        case .unknown: return "Agent"
        }
    }

    /// Template image in Assets.xcassets/AgentLogos.
    var logoAsset: String? {
        switch self {
        case .claude: return "AgentLogo-claude"
        case .codex: return "AgentLogo-openai"
        case .gemini: return "AgentLogo-gemini_cli"
        case .opencode: return "AgentLogo-opencode"
        case .amp: return "AgentLogo-amp"
        case .copilot: return "AgentLogo-copilot"
        case .cursor: return "AgentLogo-cursor"
        case .droid: return "AgentLogo-droid"
        case .goose: return "AgentLogo-goose"
        case .hermes: return "AgentLogo-hermes"
        case .unknown: return nil
        }
    }

    /// Fill of the circle behind the logo.
    var brandColor: Color {
        switch self {
        case .claude: return Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
        case .codex: return .black
        case .gemini: return Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255)
        case .opencode: return Color(white: 128 / 255)
        case .amp: return Color(red: 243 / 255, green: 78 / 255, blue: 63 / 255)
        case .copilot: return Color(red: 133 / 255, green: 52 / 255, blue: 243 / 255)
        case .cursor: return Color(red: 38 / 255, green: 37 / 255, blue: 30 / 255)
        case .droid: return .white
        case .goose: return Color(white: 16 / 255)
        case .hermes: return Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
        case .unknown: return Color(white: 0.45)
        }
    }

    /// Single-color logos are tinted; Hermes's pixel-art knight keeps its own colors.
    var logoIsTemplate: Bool { self != .hermes }

    /// Logo color on top of `brandColor`: dark on light brands, white otherwise.
    var glyphOnBrand: Color {
        self == .droid ? .black : .white
    }

    /// Logo color when drawn on its own next to the name. Near-black brands would
    /// vanish on a dark sidebar, so those fall back to the text color.
    var standaloneLogoColor: Color {
        switch self {
        case .codex, .cursor, .goose, .droid, .unknown: return .primary
        default: return brandColor
        }
    }
}
/// An agent's logo: tinted when it's a single-color mark, in full color otherwise.
struct VerticalTabAgentLogo: View {
    let kind: VerticalTabAgentKind
    let tint: Color

    var body: some View {
        if let asset = kind.logoAsset {
            if kind.logoIsTemplate {
                Image(asset).renderingMode(.template).resizable().scaledToFit().foregroundColor(tint)
            } else {
                Image(asset).resizable().interpolation(.none).scaledToFit()
            }
        }
    }
}
#endif
