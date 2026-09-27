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
            return UsageEntry(id: "claude", name: "Claude", detail: "Waiting for Claude Code to report usage",
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
        return UsageEntry(id: "claude", name: "Claude", detail: "Claude Code", agent: .claude,
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
        return UsageEntry(id: "chatgpt", name: "ChatGPT", detail: "\(plan) · Codex & Hermes", agent: .codex,
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

/// Bottom-left of the sidebar: each subscription's usage, with a bar per limit window.
struct UsagePanel: View {
    @ObservedObject private var monitor = UsageMonitor.shared
    let palette: VerticalTabsPalette
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if !monitor.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("USAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.4)
                    .foregroundColor(.secondary)
                ForEach(monitor.entries) { entry in
                    UsageRow(entry: entry, palette: palette, now: now)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .onReceive(clock) { now = $0 }
        }
    }
}

private struct UsageRow: View {
    let entry: UsageEntry
    let palette: VerticalTabsPalette
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(entry.agent.brandColor)
                    VerticalTabAgentLogo(kind: entry.agent, tint: entry.agent.glyphOnBrand).frame(width: 9, height: 9)
                }
                .frame(width: 15, height: 15)
                Text(entry.name).font(.system(size: 12, weight: .semibold))
                Text(entry.detail).font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            if entry.windows.isEmpty {
                Text("No usage reported yet").font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            ForEach(entry.windows, id: \.label) { window in
                UsageBar(window: window, palette: palette, now: now)
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

private struct UsageBar: View {
    let window: UsageWindow
    let palette: VerticalTabsPalette
    let now: Date

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
        HStack(spacing: 7) {
            Text(window.label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(color).frame(width: max(3, geometry.size.width * used / 100))
                }
            }
            .frame(height: 5)
            Text("\(Int(used.rounded()))%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .frame(width: 32, alignment: .trailing)
            Text(resetText)
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.4), value: used)
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return "" }
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60))m" }
        return "\(Int(seconds / 86_400))d \(Int(seconds.truncatingRemainder(dividingBy: 86_400) / 3600))h"
    }
}
#endif
