#if os(macOS)
import AppKit
import SwiftUI

/// Ghostty Custom's additions to the command palette (⌘P / ⌘⇧P): agents waiting on the
/// user, new sessions, and the sidebar, editor and usage toggles. Tabs already appear as
/// Ghostty's own "Focus:" entries; `agentBadge` adds each one's agent status.
enum PaletteExtras {
    /// Agents waiting for permission or an answer, shown first so they're one Enter away.
    static func waitingOptions() -> [CommandOption] {
        TerminalController.all.flatMap { controller in
            controller.surfaceTree.compactMap { surface -> CommandOption? in
                guard let info = VerticalTabsAgents.shared.info(for: surface),
                      AgentAlerts.isWaiting(info.activity) else { return nil }
                let tab = controller.titleOverride ?? surface.pwd?.abbreviatedPath
                return CommandOption(
                    title: "Answer \(info.kind.displayName): \(info.detail ?? info.activity.label)",
                    subtitle: [tab, info.task].compactMap { $0 }.joined(separator: " · "),
                    leadingIcon: info.activity == .needsPermission ? "hand.raised.fill" : "questionmark.bubble.fill",
                    leadingColor: info.kind.brandColor,
                    badge: info.activity.label,
                    emphasis: true
                ) {
                    NotificationCenter.default.post(name: Ghostty.Notification.ghosttyPresentTerminal, object: surface)
                }
            }
        }
    }

    /// New sessions and Ghostty Custom's own view toggles. Sorted in with Ghostty's commands.
    static func commandOptions(for surfaceView: Ghostty.SurfaceView) -> [CommandOption] {
        var options: [CommandOption] = []
        if let owner = surfaceView.window?.windowController as? TerminalController {
            for kind in NewSessionKind.allCases {
                options.append(CommandOption(
                    title: "New Session: \(kind.title)",
                    description: "Open a new tab running \(kind.title)",
                    leadingIcon: kind == .terminal ? "terminal" : "plus.bubble",
                    leadingColor: kind.agent?.brandColor
                ) {
                    kind.open(from: owner)
                })
            }
            for kind in DockerSessionKind.allCases {
                options.append(CommandOption(
                    title: "New Isolated Session: \(kind.title)",
                    subtitle: "Docker · \(kind.detail)",
                    description: "Open a new tab in a throwaway Docker container",
                    leadingIcon: "shippingbox",
                    leadingColor: kind.agent?.brandColor
                ) {
                    DockerSessions.open(kind, from: owner)
                })
            }
            if surfaceView.pwd != nil && !HermesSessions.shared.isHermes(owner) {
                for mode in AgentHandoff.Mode.allCases {
                    for target in AgentHandoff.targets {
                        options.append(CommandOption(
                            title: "Hand Off: \(AgentHandoff.title(mode, target))",
                            description: mode == .review
                                ? "Open \(target.displayName) beside this pane to review the changes here"
                                : "Open \(target.displayName) beside this pane to finish the task",
                            leadingIcon: "arrow.triangle.branch",
                            leadingColor: target.brandColor
                        ) {
                            AgentHandoff.handOff(from: surfaceView, in: owner, to: target, mode: mode)
                        })
                    }
                }
                options.append(CommandOption(
                    title: "Race Agents…",
                    description: "Give the same task to several agents in separate copies and keep the best",
                    symbols: ["⌃", "⌘", "R"],
                    leadingIcon: "flag.checkered.2.crossed"
                ) {
                    AgentRaces.showSetup(from: owner)
                })
            }
            if !HermesSessions.shared.isHermes(owner) {
                options.append(CommandOption(
                    title: "Toggle Code Editor",
                    description: "Show or hide this tab's code editor",
                    symbols: ["⌃", "⌘", "E"],
                    leadingIcon: "chevron.left.forwardslash.chevron.right"
                ) {
                    EditorPanel.shared.toggle(from: owner)
                })
            }
        }
        options.append(CommandOption(
            title: "Mission Control",
            description: "Every agent at a glance",
            symbols: ["⌃", "⌘", "M"],
            leadingIcon: "square.grid.2x2"
        ) {
            MissionControl.show()
        })
        options.append(CommandOption(
            title: "Toggle Vertical Tabs",
            description: "Show or hide the sidebar",
            symbols: ["⌃", "⌘", "S"],
            leadingIcon: "sidebar.left"
        ) {
            VerticalTabsMenu.shared.toggle(nil)
        })
        let showsPercent = UserDefaults.standard.bool(forKey: UsagePanel.showsPercentKey)
        options.append(CommandOption(
            title: showsPercent ? "Usage: Hide Percentages" : "Usage: Show Percentages",
            description: "Switch the sidebar's usage rings between graph and numbers",
            leadingIcon: "chart.pie"
        ) {
            UserDefaults.standard.set(!showsPercent, forKey: UsagePanel.showsPercentKey)
        })
        return options
    }

    /// The pane's agent and what it's doing, for its "Focus:" entry.
    static func agentBadge(for surface: Ghostty.SurfaceView) -> String? {
        guard let info = VerticalTabsAgents.shared.info(for: surface), info.kind != .hermes else { return nil }
        return info.activity == .ready ? info.kind.displayName : "\(info.kind.displayName) · \(info.activity.label)"
    }
}
#endif
