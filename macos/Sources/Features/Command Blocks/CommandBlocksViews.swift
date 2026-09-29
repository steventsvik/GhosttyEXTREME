#if os(macOS)
import AppKit
import SwiftUI

private enum BlockColors {
    static let success = Color(red: 0.25, green: 0.85, blue: 0.5)
    static let failure = Color(red: 1.0, green: 0.36, blue: 0.4)
    static let neutral = Color(red: 0.55, green: 0.6, blue: 0.7)

    static func color(_ block: CommandBlock) -> Color {
        guard let code = block.exitCode else { return neutral }
        if code == 0 { return success }
        return block.failed ? failure : neutral
    }

    static func agentButton(_ kind: VerticalTabAgentKind) -> Color {
        kind == .codex ? Color(red: 0.06, green: 0.64, blue: 0.5) : kind.brandColor
    }
}

// MARK: - Failure chip

/// Floats over a pane when a command fails: what failed, and one click to have an agent fix it.
struct CommandFailureChip: View {
    let surfaceView: Ghostty.SurfaceView
    @ObservedObject private var store = CommandBlocks.shared

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let block = store.failure(for: surfaceView) {
                    ViewThatFits(in: .horizontal) {
                        chip(block, compact: false)
                        chip(block, compact: true)
                    }
                        .padding(14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.failure(for: surfaceView)?.id)
    }

    private func chip(_ block: CommandBlock, compact: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(BlockColors.failure)
                Image(systemName: "xmark").font(.system(size: 10, weight: .black)).foregroundColor(.white)
            }
            .frame(width: 22, height: 22)
            .shadow(color: BlockColors.failure.opacity(0.7), radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.command)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: compact ? 150 : 260, alignment: .leading)
                Text("failed · exit \(block.exitCode ?? 1) · \(block.durationText)")
                    .font(.system(size: 10.5)).foregroundColor(BlockColors.failure)
            }
            ForEach(AgentHandoff.targets, id: \.self) { kind in
                Button {
                    store.askAgent(kind, about: block, from: surfaceView)
                } label: {
                    HStack(spacing: 5) {
                        VerticalTabAgentLogo(kind: kind, tint: .white).frame(width: 11, height: 11)
                        Text(compact ? "Fix" : kind == .claude ? "Fix with Claude" : "Fix with Codex")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, compact ? 8 : 10).padding(.vertical, 5)
                    .background(Capsule().fill(BlockColors.agentButton(kind)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Opens \(kind.displayName) in a split with the command and its output")
            }
            Button {
                if let controller = surfaceView.window?.windowController as? TerminalController {
                    CommandBlocksPanel.shared.show(controller)
                }
            } label: {
                Image(systemName: "list.bullet.rectangle").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Show command history (⌃⌘B)")
            Button { store.dismissFailure(on: surfaceView) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThickMaterial)
                RoundedRectangle(cornerRadius: 12).fill(BlockColors.failure.opacity(0.1))
            })
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LinearGradient(colors: [BlockColors.failure, .orange.opacity(0.6)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
    }
}

// MARK: - History column

/// The right-hand column with the focused pane's recent commands as blocks.
struct CommandBlocksColumn: View {
    let controller: TerminalController
    @ObservedObject private var store = CommandBlocks.shared
    @State private var failedOnly = false
    @State private var focused: Ghostty.SurfaceView?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let surface = focused ?? controller.focusedSurface
        let all = surface.map { store.blocks(for: $0) } ?? []
        let shown = Array((failedOnly ? all.filter(\.failed) : all).reversed())
        VStack(spacing: 0) {
            header(count: all.count, failures: all.filter(\.failed).count, surface: surface)
            Divider()
            if shown.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { block in
                            CommandBlockCard(block: block, surface: surface)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1) }
        .onReceive(timer) { _ in
            // Follow the focused pane as it changes.
            if focused !== controller.focusedSurface { focused = controller.focusedSurface }
        }
    }

    private func header(count: Int, failures: Int, surface: Ghostty.SurfaceView?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle.portrait.fill")
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 0) {
                Text("Command History").font(.system(size: 13, weight: .semibold))
                Text("\(count) command\(count == 1 ? "" : "s")\(failures > 0 ? " · \(failures) failed" : "") in this pane")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
            Spacer()
            Picker("", selection: $failedOnly) {
                Text("All").tag(false)
                Text("Failed").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            Menu {
                Button("Clear history") { if let surface { store.clear(surface) } }
                Button("Close") { CommandBlocksPanel.shared.toggle(controller) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal").font(.system(size: 30)).foregroundColor(.secondary)
            Text(failedOnly ? "No failed commands" : "No commands yet").font(.system(size: 13, weight: .semibold))
            Text("Commands you run in this pane show up here with their output, exit code and time. Failed ones can be sent to an agent to fix.")
                .font(.system(size: 11.5)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommandBlockCard: View {
    let block: CommandBlock
    let surface: Ghostty.SurfaceView?
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let color = BlockColors.color(block)
        let lines = block.output.split(separator: "\n", omittingEmptySubsequences: false)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text("$").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(color)
                Text(block.command)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                statusBadge(color)
                Label(block.durationText, systemImage: "timer")
                Text(RelativeDateTimeFormatter().localizedString(for: block.finished, relativeTo: Date()))
                if let cwd = block.cwd {
                    Text((cwd as NSString).lastPathComponent).lineLimit(1)
                }
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            if !block.output.isEmpty && !block.isInteractive {
                let preview = Text((expanded ? lines[...] : lines.suffix(6)).joined(separator: "\n"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if expanded {
                        ScrollView { preview }.frame(maxHeight: 360)
                    } else {
                        preview
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.28)))
                if lines.count > 6 {
                    Button(expanded ? "Show less" : "Show all \(lines.count) lines") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            if hovering, let surface {
                actions(surface)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hovering ? 0.07 : 0.045)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(block.failed ? color.opacity(0.45) : Color.primary.opacity(0.07)))
        .onHover { hovering = $0 }
    }

    private func statusBadge(_ color: Color) -> some View {
        let label: String
        if let code = block.exitCode {
            label = code == 0 ? "✓ ok" : "exit \(code)"
        } else {
            label = "done"
        }
        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private func actions(_ surface: Ghostty.SurfaceView) -> some View {
        HStack(spacing: 6) {
            small("Rerun", "arrow.clockwise") { CommandBlocks.shared.rerun(block, in: surface) }
            small("Copy", "doc.on.doc") { VerticalTabsActions.copy(block.command) }
            if !block.output.isEmpty {
                small("Copy output", "doc.plaintext") { VerticalTabsActions.copy(block.output) }
            }
            Spacer()
            ForEach(AgentHandoff.targets, id: \.self) { kind in
                Button {
                    CommandBlocks.shared.askAgent(kind, about: block, from: surface)
                } label: {
                    HStack(spacing: 4) {
                        VerticalTabAgentLogo(kind: kind, tint: .white).frame(width: 10, height: 10)
                        Text(block.failed ? "Fix" : "Explain")
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(BlockColors.agentButton(kind)))
                }
                .buttonStyle(.plain)
                .help("\(block.failed ? "Fix" : "Explain") with \(kind.displayName)")
            }
        }
    }

    private func small(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}
#endif
