#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// One usage window of a subscription, e.g. "5h" at 42% resetting in 2 hours.
struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
}

/// A subscription's current usage.
struct UsageEntry: Equatable, Identifiable {
    let id: String
    let name: String
    let detail: String
    /// Fits under the name next to the rings.
    let shortDetail: String
    let agent: VerticalTabAgentKind
    let windows: [UsageWindow]
    /// When the numbers were last reported.
    let updated: Date?
}

/// Live usage of the user's AI subscriptions, from data the tools themselves record:
///
/// - Claude: `rate_limits` from Claude Code's status line input (Pro/Max plans), which the
///   status line script saves to ~/.claude/ghostty-custom/claude-usage.json.
/// - ChatGPT plan (Codex, and Hermes when it uses the Codex provider): the `rate_limits`
///   Codex writes into its session files under ~/.codex/sessions.
///
/// Nothing here calls a network API or touches credentials. Files are re-read every 30s
/// while the app is active and right after agent activity.
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published private(set) var entries: [UsageEntry] = []

    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-custom.usage", qos: .utility)
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        center.publisher(for: VerticalTabsAgents.didChange)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            if NSApp.isActive { self?.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        queue.async {
            let entries = [Self.claude(), Self.chatGPT()].compactMap { $0 }
            DispatchQueue.main.async {
                if entries != self.entries { self.entries = entries }
            }
        }
    }

    // MARK: Claude

    private static func claude() -> UsageEntry? {
        let path = NSHomeDirectory() + "/.claude/ghostty-custom/claude-usage.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = json["rate_limits"] as? [String: Any] else {
            return UsageEntry(id: "claude", name: "Claude", detail: "Waiting for Claude Code to report usage", shortDetail: "",
                              agent: .claude, windows: [], updated: nil)
        }
        func window(_ key: String, _ label: String) -> UsageWindow? {
            guard let w = limits[key] as? [String: Any], let used = w["used_percentage"] as? Double else { return nil }
            return UsageWindow(label: label, usedPercent: used,
                               resetsAt: (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) })
        }
        let windows = [window("five_hour", "5h"), window("seven_day", "Week"), window("spend_limit", "Spend")]
            .compactMap { $0 }
        let updated = (json["updated"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return UsageEntry(id: "claude", name: "Claude", detail: "Claude Code", shortDetail: "Code", agent: .claude,
                          windows: windows, updated: updated)
    }

    // MARK: ChatGPT (Codex / Hermes)

    private static func chatGPT() -> UsageEntry? {
        guard let (limits, updated) = latestCodexRateLimits() else { return nil }
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = limits[key] as? [String: Any], let used = w["used_percent"] as? Double else { continue }
            let minutes = w["window_minutes"] as? Double ?? 0
            let label = minutes >= 10_000 ? "Week" : minutes >= 1_440 ? "\(Int(minutes / 1_440))d" : minutes > 0 ? "\(Int(minutes / 60))h" : "Limit"
            windows.append(UsageWindow(label: label, usedPercent: used,
                                       resetsAt: (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }))
        }
        let plan = (limits["plan_type"] as? String).map(planName) ?? "ChatGPT"
        return UsageEntry(id: "chatgpt", name: "ChatGPT", detail: "\(plan) · Codex & Hermes", shortDetail: plan, agent: .codex,
                          windows: windows, updated: updated)
    }

    private static func planName(_ raw: String) -> String {
        switch raw {
        case "prolite": return "Pro Lite"
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return raw.capitalized
        }
    }

    /// The most recent `rate_limits` record across the newest Codex session files.
    private static func latestCodexRateLimits() -> ([String: Any], Date?)? {
        let root = NSHomeDirectory() + "/.codex/sessions"
        let fm = FileManager.default
        // Sessions are stored as YYYY/MM/DD/rollout-*.jsonl; walk the newest days first.
        func newest(_ dir: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted(by: >)
        }
        var files: [(path: String, modified: Date)] = []
        outer: for year in newest(root) {
            for month in newest("\(root)/\(year)") {
                for day in newest("\(root)/\(year)/\(month)") {
                    let dir = "\(root)/\(year)/\(month)/\(day)"
                    for name in newest(dir) where name.hasSuffix(".jsonl") {
                        let path = "\(dir)/\(name)"
                        let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                        files.append((path, modified))
                    }
                    if files.count >= 6 { break outer }
                }
            }
        }
        for file in files.sorted(by: { $0.modified > $1.modified }).prefix(6) {
            guard let handle = FileHandle(forReadingAtPath: file.path) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
            guard let text = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let payload = json["payload"] as? [String: Any],
                      let limits = payload["rate_limits"] as? [String: Any] else { continue }
                return (limits, file.modified)
            }
        }
        return nil
    }
}

// MARK: - View

/// Bottom-left of the sidebar: each subscription's usage as a row of ring gauges, one per
/// limit window. The rings fill and change color as usage grows; clicking the panel
/// shows the exact percentages and time until each window resets.
struct UsagePanel: View {
    @ObservedObject private var monitor = UsageMonitor.shared
    let palette: VerticalTabsPalette
    @AppStorage("GhosttyCustomUsageShowsPercent") private var showsPercent = false
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if !monitor.entries.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("USAGE")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.4)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: showsPercent ? "percent" : "chart.pie")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                ForEach(monitor.entries) { entry in
                    UsageRow(entry: entry, showsPercent: showsPercent, now: now)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showsPercent.toggle() }
            }
            .help(showsPercent ? "Click to hide percentages" : "Click to show percentages")
            .onReceive(clock) { now = $0 }
        }
    }
}

private struct UsageRow: View {
    let entry: UsageEntry
    let showsPercent: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle().fill(entry.agent.brandColor)
                VerticalTabAgentLogo(kind: entry.agent, tint: entry.agent.glyphOnBrand).frame(width: 11, height: 11)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 12, weight: .semibold))
                Text(entry.windows.isEmpty ? "No usage yet" : entry.shortDetail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 4)
            HStack(alignment: .top, spacing: 7) {
                ForEach(entry.windows, id: \.label) { window in
                    UsageRing(window: window, showsPercent: showsPercent, now: now)
                }
            }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        var lines = [entry.detail]
        for window in entry.windows {
            let resets = window.resetsAt.map { "resets \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short))" } ?? ""
            lines.append("\(window.label): \(Int(window.usedPercent.rounded()))% used \(resets)")
        }
        if let updated = entry.updated {
            lines.append("Reported \(RelativeDateTimeFormatter().localizedString(for: updated, relativeTo: now))")
        }
        return lines.joined(separator: "\n")
    }
}

/// One limit window as a ring that fills clockwise with usage.
private struct UsageRing: View {
    let window: UsageWindow
    let showsPercent: Bool
    let now: Date

    private static let size: CGFloat = 32

    /// A window that has already reset shows as unused until new numbers arrive.
    private var used: Double {
        if let resetsAt = window.resetsAt, resetsAt <= now { return 0 }
        return min(max(window.usedPercent, 0), 100)
    }

    /// Fixed traffic-light colors: usage levels need to read the same in every theme
    /// (some themes' "green" palette slot isn't green).
    private var color: Color {
        used >= 90 ? Color(red: 0.96, green: 0.36, blue: 0.33)
            : used >= 70 ? Color(red: 0.98, green: 0.76, blue: 0.25)
            : Color(red: 0.35, green: 0.80, blue: 0.47)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.015, used / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.45), radius: 2)
                if showsPercent {
                    Text("\(Int(used.rounded()))%")
                        .font(.system(size: used >= 100 ? 8.5 : 9.5, weight: .bold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Circle().fill(color).frame(width: 5, height: 5)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: Self.size, height: Self.size)
            .padding(2)
            Text(window.label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary)
            if showsPercent, let reset = resetText {
                Text(reset)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.secondary.opacity(0.8))
                    .transition(.opacity)
            }
        }
        .frame(minWidth: Self.size + 6)
        .animation(.easeOut(duration: 0.6), value: used)
    }

    private var resetText: String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m" }
        return "\(Int(seconds / 86_400))d \(Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600))h"
    }
}
#endif
