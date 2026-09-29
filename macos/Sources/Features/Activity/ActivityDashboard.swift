#if os(macOS)
import AppKit
import Charts
import SwiftUI

/// Agent activity over time: how long agents worked, on what, and how much they changed.
enum ActivityDashboard {
    static let windowID = "activity"

    static func toggle() {
        if AgentToolWindows.isOpen(windowID) {
            AgentToolWindows.close(id: windowID)
        } else {
            AgentToolWindows.show(id: windowID, title: "Agent Activity", size: NSSize(width: 1180, height: 820)) {
                ActivityDashboardView()
            }
        }
    }
}

private enum ActivityRange: String, CaseIterable, Identifiable {
    case today = "Today", week = "7 days", month = "30 days"
    var id: Self { self }

    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }

    var start: Date {
        Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!
    }
}

private enum ActivityColors {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.06, green: 0.72, blue: 0.56)

    static func agent(_ id: String) -> Color { id == "codex" ? codex : claude }

    static let tiles: [[Color]] = [
        [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.4, blue: 1.0)],
        [Color(red: 1.0, green: 0.45, blue: 0.62), Color(red: 1.0, green: 0.62, blue: 0.35)],
        [Color(red: 0.2, green: 0.8, blue: 0.9), Color(red: 0.25, green: 0.55, blue: 1.0)],
        [Color(red: 0.3, green: 0.88, blue: 0.55), Color(red: 0.1, green: 0.7, blue: 0.7)],
        [Color(red: 1.0, green: 0.72, blue: 0.25), Color(red: 1.0, green: 0.45, blue: 0.35)],
        [Color(red: 0.75, green: 0.45, blue: 1.0), Color(red: 1.0, green: 0.4, blue: 0.75)],
    ]
}

private struct DayBar: Identifiable {
    let day: Date
    let agent: String
    let minutes: Double
    var id: String { "\(day.timeIntervalSince1970)-\(agent)" }
}

private final class ActivityModel: ObservableObject {
    @Published var sessions: [ActivitySession] = []
    @Published var loading = false
    @Published var range: ActivityRange = .week {
        didSet { load() }
    }

    func load() {
        loading = true
        let start = range.start
        DispatchQueue.global(qos: .userInitiated).async {
            let sessions = ActivityStats.shared.sessions(since: start)
                .filter { ($0.end ?? .distantPast) >= start }
            DispatchQueue.main.async {
                self.sessions = sessions
                self.loading = false
            }
        }
    }

    private var dayKeys: [String] {
        (0..<range.days).map { offset in
            ActivityStats.dayKey(Calendar.current.date(byAdding: .day, value: offset, to: range.start)!)
        }
    }

    /// Active seconds within the range only (sessions can start before it).
    func active(_ session: ActivitySession) -> Double {
        let keys = Set(dayKeys)
        return session.activeByDay.filter { keys.contains($0.key) }.values.reduce(0, +)
    }

    var totalActive: Double { sessions.map(active).reduce(0, +) }

    var bars: [DayBar] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var result: [DayBar] = []
        for key in dayKeys {
            guard let day = formatter.date(from: key) else { continue }
            for agent in ["claude", "codex"] {
                let seconds = sessions.filter { $0.agent == agent }.compactMap { $0.activeByDay[key] }.reduce(0, +)
                result.append(DayBar(day: day, agent: agent, minutes: seconds / 60))
            }
        }
        return result
    }

    var byHour: [Double] {
        (0..<24).map { hour in sessions.compactMap { $0.activeByHour[hour] }.reduce(0, +) }
    }

    struct ProjectRow: Identifiable {
        let name: String
        let claude: Double
        let codex: Double
        let sessions: Int
        let prompts: Int
        let files: Int
        let lines: Int
        var id: String { name }
        var total: Double { claude + codex }
    }

    var projects: [ProjectRow] {
        var rows: [ProjectRow] = []
        for (name, list) in Dictionary(grouping: sessions, by: \.project) {
            let claude: Double = list.filter { $0.agent == "claude" }.map(active).reduce(0, +)
            let codex: Double = list.filter { $0.agent == "codex" }.map(active).reduce(0, +)
            let prompts: Int = list.map(\.prompts).reduce(0, +)
            let files: Int = Set(list.flatMap(\.files)).count
            let lines: Int = list.map { $0.linesAdded + $0.linesRemoved }.reduce(0, +)
            rows.append(ProjectRow(name: name, claude: claude, codex: codex, sessions: list.count,
                                   prompts: prompts, files: files, lines: lines))
        }
        return rows.sorted { $0.total > $1.total }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

private func formatCount(_ value: Int) -> String {
    if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
    if value >= 10_000 { return String(format: "%.1fK", Double(value) / 1000) }
    return "\(value)"
}

private struct ActivityDashboardView: View {
    @StateObject private var model = ActivityModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tiles
                    HStack(alignment: .top, spacing: 16) {
                        dailyChart.frame(maxWidth: .infinity)
                        agentSplit.frame(width: 280)
                    }
                    hourStrip
                    HStack(alignment: .top, spacing: 16) {
                        projectsTable.frame(maxWidth: .infinity)
                        recentSessions.frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.04), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear { model.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0), .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "chart.bar.xaxis").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 34, height: 34)
            .shadow(color: .blue.opacity(0.4), radius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Activity").font(.system(size: 17, weight: .bold))
                Text("From Claude Code and Codex session history on this Mac")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
            Picker("", selection: $model.range) {
                ForEach(ActivityRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 12)
    }

    private var tiles: some View {
        let sessions = model.sessions
        let files = Set(sessions.flatMap(\.files)).count
        let lines = sessions.map { $0.linesAdded + $0.linesRemoved }.reduce(0, +)
        let items: [(String, String, String, String)] = [
            ("clock.fill", "Active time", formatDuration(model.totalActive), "\(sessions.count) session\(sessions.count == 1 ? "" : "s")"),
            ("text.bubble.fill", "Prompts", "\(sessions.map(\.prompts).reduce(0, +))", "\(sessions.map(\.toolCalls).reduce(0, +)) tool calls"),
            ("doc.text.fill", "Files changed", "\(files)", "\(formatCount(lines)) lines"),
            ("terminal.fill", "Commands", "\(sessions.map(\.commands).reduce(0, +))", "\(sessions.map(\.tests).reduce(0, +)) test runs"),
            ("arrow.down.circle.fill", "Tokens in", formatCount(sessions.map(\.tokensIn).reduce(0, +)), "incl. cached context"),
            ("arrow.up.circle.fill", "Tokens out", formatCount(sessions.map(\.tokensOut).reduce(0, +)), "written by agents"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let colors = ActivityColors.tiles[index % ActivityColors.tiles.count]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: item.0).font(.system(size: 12, weight: .bold))
                        Text(item.1).font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    Text(item.2).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text(item.3).font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: colors[0].opacity(0.35), radius: 10, y: 4)
            }
        }
    }

    private func card<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor).opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }

    private var dailyChart: some View {
        card("Active time per day", "chart.bar.fill") {
            Chart(model.bars) { bar in
                BarMark(
                    x: .value("Day", bar.day, unit: .day),
                    y: .value("Minutes", bar.minutes))
                .foregroundStyle(by: .value("Agent", bar.agent == "codex" ? "Codex" : "Claude Code"))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(["Claude Code": ActivityColors.claude, "Codex": ActivityColors.codex])
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { if let minutes = value.as(Double.self) { Text(formatDuration(minutes * 60)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: model.range == .month ? 5 : 1)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day())
                }
            }
            .frame(height: 210)
        }
    }

    private var agentSplit: some View {
        let claude = model.sessions.filter { $0.agent == "claude" }.map(model.active).reduce(0, +)
        let codex = model.sessions.filter { $0.agent == "codex" }.map(model.active).reduce(0, +)
        return card("By agent", "person.2.fill") {
            let total = max(claude + codex, 1)
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 5).fill(ActivityColors.claude)
                            .frame(width: max(4, geometry.size.width * claude / total))
                        RoundedRectangle(cornerRadius: 5).fill(ActivityColors.codex)
                    }
                }
                .frame(height: 16)
                ForEach([("claude", claude), ("codex", codex)], id: \.0) { agent, seconds in
                    let kind = VerticalTabAgentKind(id: agent)
                    let list = model.sessions.filter { $0.agent == agent }
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(ActivityColors.agent(agent))
                            VerticalTabAgentLogo(kind: kind, tint: .white).frame(width: 13, height: 13)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.displayName).font(.system(size: 12.5, weight: .semibold))
                            Text("\(list.count) sessions · \(list.map(\.prompts).reduce(0, +)) prompts")
                                .font(.system(size: 10.5)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatDuration(seconds)).font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(ActivityColors.agent(agent))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 210)
        }
    }

    private var hourStrip: some View {
        let hours = model.byHour
        let peak = max(hours.max() ?? 1, 1)
        return card("When agents work", "clock.arrow.2.circlepath") {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<24, id: \.self) { hour in
                        let level = hours[hour] / peak
                        RoundedRectangle(cornerRadius: 5)
                            .fill(level == 0 ? AnyShapeStyle(Color.primary.opacity(0.06))
                                  : AnyShapeStyle(LinearGradient(colors: [Color.cyan.opacity(0.35 + level * 0.65), Color.purple.opacity(0.3 + level * 0.7)],
                                                                 startPoint: .bottom, endPoint: .top)))
                            .frame(height: 34)
                            .help("\(hour):00 · \(formatDuration(hours[hour]))")
                    }
                }
                HStack {
                    ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                        Text(hour == 0 ? "12am" : hour == 12 ? "12pm" : hour < 12 ? "\(hour)am" : "\(hour - 12)pm")
                            .font(.system(size: 9.5)).foregroundColor(.secondary)
                        if hour != 23 { Spacer() }
                    }
                }
            }
        }
    }

    private var projectsTable: some View {
        card("Projects", "folder.fill") {
            if model.projects.isEmpty {
                Text("No agent activity in this period.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            let peak = max(model.projects.first?.total ?? 1, 1)
            VStack(spacing: 10) {
                ForEach(model.projects.prefix(12)) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(LocalhostProject(folder: project.name).color).frame(width: 8, height: 8)
                            Text(project.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text("\(project.prompts) prompts · \(project.files) files · \(formatCount(project.lines)) lines")
                                .font(.system(size: 10.5)).foregroundColor(.secondary)
                            Text(formatDuration(project.total)).font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(width: 58, alignment: .trailing)
                        }
                        GeometryReader { geometry in
                            HStack(spacing: 1) {
                                Capsule().fill(ActivityColors.claude).frame(width: geometry.size.width * project.claude / peak)
                                Capsule().fill(ActivityColors.codex).frame(width: geometry.size.width * project.codex / peak)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private var recentSessions: some View {
        card("Recent sessions", "list.bullet.rectangle.fill") {
            if model.sessions.isEmpty {
                Text("No sessions in this period.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(model.sessions.prefix(14)) { session in
                    ActivitySessionRow(session: session, active: model.active(session))
                }
            }
        }
    }
}

private struct ActivitySessionRow: View {
    let session: ActivitySession
    let active: Double
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(ActivityColors.agent(session.agent))
                VerticalTabAgentLogo(kind: session.kind, tint: .white).frame(width: 11, height: 11)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.project)
                    if let end = session.end {
                        Text("· " + RelativeDateTimeFormatter().localizedString(for: end, relativeTo: Date()))
                    }
                    if !session.files.isEmpty { Text("· \(session.files.count) files") }
                }
                .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if hovering, session.cwd != nil {
                Button("Resume") { resume() }
                    .controlSize(.small)
                    .help("Continue this session in a new tab")
            } else {
                Text(formatDuration(active)).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(ActivityColors.agent(session.agent))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.07 : 0.03)))
        .onHover { hovering = $0 }
    }

    private func resume() {
        guard let cwd = session.cwd,
              let owner = TerminalController.all.first(where: { $0.window?.isVisible == true }) ?? TerminalController.all.first else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = cwd
        let id = AgentTools.shellQuote(session.id)
        config.initialInput = (session.agent == "codex" ? "codex resume \(id)" : "claude --resume \(id)") + "\n"
        if let controller = TerminalController.newTab(owner.ghostty, from: owner.window, withBaseConfig: config) {
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }
}
#endif
