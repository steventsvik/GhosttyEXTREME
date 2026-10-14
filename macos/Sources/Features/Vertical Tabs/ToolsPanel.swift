#if os(macOS)
import SwiftUI

/// The sidebar's "Tools" button: every tool by name, with what it's for and its shortcut,
/// including the ones that don't fit as icons in the header.
struct ToolsButton: View {
    let owner: TerminalController
    @Binding var condensed: Bool
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let lit = open || hovering
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Text("Tools").font(Extreme.font(11.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .fixedSize()
            .foregroundColor(lit ? Extreme.gold : Extreme.text.opacity(0.85))
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(shape.fill(lit ? Extreme.raised : Extreme.panel))
            .overlay(shape.strokeBorder(lit ? Extreme.gold.opacity(0.55) : Extreme.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: lit)
        .help("Every tool, with its shortcut")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ToolsPanel(owner: owner, condensed: $condensed) { action in
                open = false
                // After the popover closes, so a window it opens comes to the front.
                DispatchQueue.main.async(execute: action)
            }
        }
    }
}

private struct ToolsPanel: View {
    let owner: TerminalController
    @Binding var condensed: Bool
    let run: (@escaping () -> Void) -> Void
    @ObservedObject private var settings = ExtremeSettings.shared

    private struct Tool: Identifiable {
        let feature: ExtremeFeature?
        let symbol: String
        let title: String
        let detail: String
        var shortcut: String?
        let action: () -> Void
        var id: String { title }
    }

    private var tools: [Tool] {
        let pwd = owner.focusedSurface?.pwd
        let hermes = HermesSessions.shared.isHermes(owner)
        var all: [Tool] = []
        func add(_ feature: ExtremeFeature, _ symbol: String, _ title: String, _ detail: String,
                 _ action: @escaping () -> Void) {
            guard settings.isOn(feature) else { return }
            all.append(Tool(feature: feature, symbol: symbol, title: title, detail: detail,
                            shortcut: feature.shortcut, action: action))
        }
        if !hermes {
            add(.editor, PixelIcon.code.symbol, "Code editor", "Watch the agent edit, live") { EditorPanel.shared.toggle(from: owner) }
            add(.visualFix, PixelIcon.target.symbol, "Visual Fix", "Point at your app, have it changed") { VisualFixPanel.shared.toggle(owner) }
        }
        add(.missionControl, PixelIcon.grid.symbol, "Mission Control", "Every agent as a live card", MissionControl.toggle)
        add(.review, PixelIcon.inbox.symbol, "Review changes", "Each agent's finished work", ReviewInbox.toggle)
        add(.localhost, PixelIcon.globe.symbol, "Localhost", "Dev servers your agents started", LocalhostManager.toggle)
        add(.activity, PixelIcon.chart.symbol, "Agent activity", "Time, prompts, files and tokens", ActivityDashboard.toggle)
        add(.skills, PixelIcon.skills.symbol, "Skills", "Installed skills, updates, trending") { SkillsWindow.show(folder: pwd) }
        if pwd != nil {
            add(.memory, PixelIcon.memory.symbol, "Project memory", "What your agents remember here") { MemoryWindow.show(folder: pwd) }
        }
        add(.environment, PixelIcon.environment.symbol, "Environment", "Tool versions, containers, models") { EnvironmentWindow.show(folder: pwd) }
        add(.background, "gauge.with.dots.needle.67percent", "Background processes", "Servers and agents left running", HousekeepingWindow.show)
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tools) { tool in
                ToolsPanelRow(symbol: tool.symbol, title: tool.title, detail: tool.detail,
                              shortcut: tool.shortcut.map { "⌃⌘" + $0 }) { run(tool.action) }
            }
            Rectangle().fill(Extreme.line).frame(height: 1).padding(.vertical, 4)
            ToolsPanelRow(symbol: (condensed ? PixelIcon.expand : .condense).symbol,
                          title: condensed ? "Expand view" : "Condense view",
                          detail: condensed ? "Show agent details on each tab" : "One line per tab") {
                run { condensed.toggle() }
            }
            ToolsPanelRow(symbol: "gearshape", title: "Settings", detail: "Turn tools on or off",
                          shortcut: "⌃⌘,") { run(ExtremeSettingsWindow.show) }
        }
        .padding(6)
        .frame(width: 300)
        .background(Extreme.panel)
        .environment(\.colorScheme, .dark)
    }
}

private struct ToolsPanelRow: View {
    let symbol: String
    let title: String
    let detail: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hovering ? Extreme.gold : Extreme.text.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Extreme.ink))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(hovering ? Extreme.gold.opacity(0.5) : Extreme.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Extreme.font(11.5, weight: .semibold))
                        .foregroundColor(hovering ? Extreme.gold : Extreme.text)
                    Text(detail).font(Extreme.font(10)).foregroundColor(Extreme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if let shortcut {
                    Text(shortcut).font(Extreme.mono(10)).foregroundColor(Extreme.dim)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Extreme.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif
