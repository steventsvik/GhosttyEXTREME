#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Shared pieces

/// A square status light that blinks in steps while the server is live.
struct LocalhostPulse: View {
    let color: Color
    let active: Bool
    var size: CGFloat = 6

    var body: some View {
        PixelDot(color: color, blinking: active, size: size)
    }
}

/// The framework's badge: its name in its color, in a hairline box.
struct LocalhostFrameworkBadge: View {
    let framework: LocalhostFramework
    var compact = false

    var body: some View {
        Text(compact ? String(framework.name.prefix(3)).uppercased() : framework.name.uppercased())
            .font(Extreme.font(8.5))
            .kerning(1.2)
            .foregroundColor(framework.color == .white ? Extreme.text : framework.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .overlay(Rectangle().strokeBorder(Extreme.line, lineWidth: 1))
            .fixedSize()
    }
}

/// `localhost:5173 ↗`: the thing you click to open the app.
struct LocalhostURLPill: View {
    let session: LocalhostSession
    var large = false
    @State private var hovering = false

    var body: some View {
        Button {
            LocalhostSessions.shared.openInBrowser(session.url)
        } label: {
            HStack(spacing: 5) {
                if let port = session.ports.first {
                    Text("localhost").foregroundColor(Extreme.muted)
                        + Text(verbatim: ":\(port)").foregroundColor(Extreme.gold)
                    Text("↗").foregroundColor(hovering ? Extreme.gold : Extreme.dim)
                } else {
                    Text(session.state == .starting ? "starting…" : "not listening").foregroundColor(Extreme.dim)
                }
            }
            .font(Extreme.font(large ? 13 : 11))
            .padding(.horizontal, large ? 10 : 7)
            .padding(.vertical, large ? 5 : 3)
            .background(hovering ? Extreme.raised : Extreme.ink)
            .overlay(Rectangle().strokeBorder(hovering ? Extreme.lineStrong : Extreme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.url == nil)
        .onHover { hovering = $0 }
        .help(session.url.map { "Open \($0.absoluteString) in your browser" } ?? "")
    }
}

/// Square icon button used on cards (takes an SF Symbol name for the manager's controls).
struct LocalhostIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = Extreme.gold
    var size: CGFloat = 22
    let action: () -> Void
    @State private var hovering = false

    private var pixelIcon: PixelIcon? {
        switch symbol {
        case "arrow.clockwise": return .restart
        case "stop.fill": return .stop
        case "play.fill": return .play
        case "xmark": return .close
        case "eye": return .eye
        default: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let pixelIcon {
                    PixelIconView(icon: pixelIcon, color: hovering ? tint : Extreme.muted, pixel: 1)
                } else {
                    Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold))
                        .foregroundColor(hovering ? tint : Extreme.muted)
                }
            }
            .frame(width: size, height: size)
            .background(hovering ? Extreme.raised : Color.clear)
            .overlay(Rectangle().strokeBorder(hovering ? Extreme.lineStrong : Extreme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

func localhostUptime(since date: Date?, now: Date) -> String {
    guard let date else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
}

// MARK: - Sidebar

/// The LOCALHOST block above the usage panel: one row per session tab.
struct LocalhostSidebarSection: View {
    let entries: [VerticalTabEntry]
    let owner: TerminalController
    @ObservedObject private var store = LocalhostSessions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ExtremeSectionLabel("Localhost") {
                if store.liveCount > 0 {
                    Text("\(store.liveCount) LIVE").font(Extreme.font(9)).kerning(1.2).foregroundColor(Extreme.live)
                }
                Button { LocalhostManager.show() } label: {
                    PixelIconView(icon: .grid, color: Extreme.muted, pixel: 1).frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("Localhost manager (⌃⌘L)")
                Button { LocalhostManager.showNewServer(folder: owner.focusedSurface?.pwd, from: owner) } label: {
                    PixelIconView(icon: .plus, color: Extreme.muted, pixel: 1).frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help("New localhost server")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            // Four rows show at once; more scroll.
            if entries.count > 4 {
                ScrollView { rows }.frame(height: 4 * 44)
            } else {
                rows
            }
        }
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.15), value: entries.map(\.id))
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                if let controller = entry.controller, let session = store.session(for: controller) {
                    LocalhostTabCard(session: session, controller: controller, isSelected: controller === owner)
                        .padding(.horizontal, 8)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// A localhost session in the sidebar: status light, project and port; controls on hover.
struct LocalhostTabCard: View {
    let session: LocalhostSession
    let controller: TerminalController
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        let live = session.state == .live
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if session.state == .starting {
                        PixelSpinner(color: Extreme.warn, pixel: 2)
                    } else {
                        PixelDot(color: session.statusColor, size: 6)
                    }
                    Text(session.project.name)
                        .font(Extreme.font(12))
                        .foregroundColor(isSelected ? Extreme.text : Extreme.text.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if hovering {
                        controls
                    } else if let port = session.ports.first {
                        Button { LocalhostSessions.shared.openInBrowser(session.url) } label: {
                            Text(verbatim: ":\(port)").font(Extreme.font(12)).foregroundColor(Extreme.gold)
                        }
                        .buttonStyle(.plain)
                        .help("Open \(session.url?.absoluteString ?? "") in your browser")
                    } else {
                        Text(session.statusLabel.lowercased()).font(Extreme.font(10)).foregroundColor(session.statusColor)
                    }
                }
                HStack(spacing: 6) {
                    Text(session.framework.name.uppercased()).kerning(1)
                        .foregroundColor(session.framework.color == .white ? Extreme.muted : session.framework.color.opacity(0.85))
                    if live, let since = session.liveSince {
                        Text("· \(localhostUptime(since: since, now: context.date))")
                    } else if !live {
                        Text("· \(session.statusLabel.lowercased())")
                    }
                    if let agent = session.agent {
                        Text("· by \(agent.displayName)")
                    }
                    Spacer(minLength: 0)
                }
                .font(Extreme.font(9))
                .foregroundColor(Extreme.dim)
                .lineLimit(1)
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Extreme.raised : (hovering ? Extreme.raised.opacity(0.6) : Color.clear))
        .overlay(Rectangle().strokeBorder(isSelected ? Extreme.live.opacity(0.7) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { LocalhostSessions.shared.focus(session) }
        .contextMenu { menu }
        .help("\(session.command)\n\(session.cwd)")
    }

    private var controls: some View {
        HStack(spacing: 3) {
            LocalhostIconButton(symbol: "eye", help: "Preview in GhosttyEXTREME", tint: Extreme.core, size: 18) {
                if let url = session.url { LocalhostPreview.show(url, title: session.project.name) }
            }
            .disabled(session.url == nil)
            LocalhostIconButton(symbol: session.isRunning ? "arrow.clockwise" : "play.fill",
                                help: session.isRunning ? "Restart" : "Start again", tint: Extreme.warn, size: 18) {
                LocalhostSessions.shared.restart(session)
            }
            if session.isRunning {
                LocalhostIconButton(symbol: "stop.fill", help: "Stop the server (the tab stays)", tint: Extreme.danger, size: 18) {
                    LocalhostSessions.shared.stop(session)
                }
            }
            LocalhostIconButton(symbol: "xmark", help: "Stop and close the tab", tint: Extreme.danger, size: 18) {
                LocalhostSessions.shared.close(session)
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open in Browser") { LocalhostSessions.shared.openInBrowser(session.url) }.disabled(session.url == nil)
        Button("Preview in GhosttyEXTREME") {
            if let url = session.url { LocalhostPreview.show(url, title: session.project.name) }
        }.disabled(session.url == nil)
        Button("Copy URL") { VerticalTabsActions.copy(session.url?.absoluteString ?? "") }.disabled(session.url == nil)
        Divider()
        Button(session.isRunning ? "Restart" : "Start Again") { LocalhostSessions.shared.restart(session) }
        Button("Stop Server") { LocalhostSessions.shared.stop(session) }.disabled(!session.isRunning)
        Button("Show Logs") { LocalhostSessions.shared.focus(session) }
        Divider()
        Button("Open Localhost Manager") { LocalhostManager.show() }
        Button("Stop and Close Tab") { LocalhostSessions.shared.close(session) }
    }
}

/// Sidebar header button: opens the localhost manager, with the live count.
struct LocalhostHeaderButton: View {
    @ObservedObject private var store = LocalhostSessions.shared

    var body: some View {
        ExtremeIconButton(icon: .globe, help: "Localhost manager (⌃⌘L)",
                          tint: Extreme.live, badge: store.liveCount, badgeColor: Extreme.live,
                          action: LocalhostManager.toggle)
    }
}

// MARK: - Toast

/// "Your app is live" pop-up shown over the terminal when a session starts listening.
struct LocalhostToastView: View {
    let session: LocalhostSession
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PixelIconView(icon: .globe, color: Extreme.live, pixel: 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(session.project.name.uppercased()) IS LIVE")
                        .font(Extreme.font(11)).kerning(1.6).foregroundColor(Extreme.gold)
                    LocalhostFrameworkBadge(framework: session.framework, compact: true)
                }
                Text(session.agent.map { "started by \($0.displayName) · its own tab · keeps running" } ?? "running in its own tab")
                    .font(Extreme.font(10)).foregroundColor(Extreme.muted).lineLimit(1)
            }
            LocalhostURLPill(session: session, large: true)
            Button(action: dismiss) { PixelIconView(icon: .close, color: Extreme.dim, pixel: 1) }
                .buttonStyle(.plain)
                .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .extremePanel(active: true, fill: Extreme.ink)
        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
        .fixedSize()
    }
}

/// Places the toast at the top of the terminal area.
struct LocalhostToastLayer: View {
    @ObservedObject private var store = LocalhostSessions.shared

    var body: some View {
        VStack {
            if let session = store.toast {
                LocalhostToastView(session: session) { store.toast = nil }
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { LocalhostSessions.shared.focus(session) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: store.toast?.id)
    }
}
#endif
