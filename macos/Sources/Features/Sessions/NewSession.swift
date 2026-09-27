#if os(macOS)
import AppKit
import SwiftUI

/// The kinds of session the sidebar's "New" menu can open, like Warp's new-session menu.
enum NewSessionKind: CaseIterable, Identifiable {
    case terminal
    case claude
    case codex
    case hermes
    case cloudClaude

    var id: Self { self }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .hermes: return "Hermes"
        case .cloudClaude: return "Cloud Agent · Claude Code"
        }
    }

    var agent: VerticalTabAgentKind? {
        switch self {
        case .terminal: return nil
        case .claude, .cloudClaude: return .claude
        case .codex: return .codex
        case .hermes: return .hermes
        }
    }

    /// Typed into a normal shell, so the shell's features stay and exiting the agent
    /// returns to the prompt.
    var command: String? {
        switch self {
        case .terminal, .hermes: return nil
        case .claude: return "claude"
        case .codex: return "codex"
        // A Claude Code cloud session (runs on Anthropic's servers, same as claude.ai/code).
        case .cloudClaude: return "claude --cloud"
        }
    }

    func open(from owner: TerminalController) {
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = owner.focusedSurface?.pwd
        if let command { config.initialInput = command + "\n" }
        guard let controller = TerminalController.newTab(owner.ghostty, from: owner.window, withBaseConfig: config) else { return }
        if self == .hermes {
            HermesSessions.shared.adopt(controller)
        }
    }
}

/// "+ New" in the sidebar header: a menu of session kinds with their logos.
struct NewSessionMenu: View {
    let owner: TerminalController
    let compact: Bool
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(NewSessionKind.allCases) { kind in
                if kind == .hermes || kind == .cloudClaude { Divider() }
                Button {
                    kind.open(from: owner)
                } label: {
                    Label {
                        Text(kind.title)
                    } icon: {
                        icon(for: kind)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text(compact ? "New" : "New tab").font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.14), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }

    /// Menu item icons are rendered as images, so draw each logo into one.
    private func icon(for kind: NewSessionKind) -> Image {
        if let agent = kind.agent, let asset = agent.logoAsset, let image = NSImage(named: asset) {
            let copy = image.copy() as! NSImage
            copy.size = NSSize(width: 16, height: 16)
            copy.isTemplate = agent.logoIsTemplate
            return Image(nsImage: copy)
        }
        return Image(systemName: kind == .cloudClaude ? "cloud" : "apple.terminal")
    }
}
#endif
