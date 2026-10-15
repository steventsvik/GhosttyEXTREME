#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Local Models window: the models Ollama has, each opened as a Claude Code session,
/// and a few to download.
enum LocalModelsWindow {
    static let windowID = "local-models"

    static func show() {
        guard ExtremeSettings.isOn(.localModels) else { return }
        AgentToolWindows.show(id: windowID, title: "Local Models", size: NSSize(width: 640, height: 560)) {
            LocalModelsWindowView()
        }
    }

    /// The terminal window in front of the others, to open a model in.
    static var frontTerminal: TerminalController? {
        NSApp.orderedWindows.lazy.compactMap { $0.windowController as? TerminalController }.first
            ?? TerminalController.all.first
    }
}

/// Models worth starting with, smallest first. All of them can use tools, which Claude Code needs.
private struct SuggestedModel: Identifiable {
    let name: String
    let size: String
    let bytes: Int64
    let note: String
    var id: String { name }

    static let all = [
        SuggestedModel(name: "qwen3:4b", size: "2.5 GB", bytes: 2_500_000_000, note: "Quick, for small edits and questions"),
        SuggestedModel(name: "qwen3:8b", size: "5.2 GB", bytes: 5_200_000_000, note: "A good balance on 16 GB Macs"),
        SuggestedModel(name: "gpt-oss:20b", size: "14 GB", bytes: 14_000_000_000, note: "OpenAI's open model; needs 24 GB or more"),
        SuggestedModel(name: "qwen3-coder:30b", size: "19 GB", bytes: 19_000_000_000, note: "Best for code; needs 32 GB or more"),
    ]
}

struct LocalModelsWindowView: View {
    @ObservedObject private var models = LocalModelsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtremeWindowTitle(icon: .environment, title: "Local Models",
                               subtitle: "Claude Code on a model on this Mac. Drag one from the sidebar under a chat.")
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 14)
            Rectangle().fill(Extreme.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    status
                    if let error = models.error {
                        Text(error).font(Extreme.font(12)).foregroundColor(Extreme.danger)
                    }
                    let installed = models.models.filter { $0.host == .ollama }
                    if !installed.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ExtremeSectionLabel("On this Mac")
                            ForEach(installed) { LocalModelWindowRow(item: $0) }
                        }
                    }
                    if case .running = models.ollama {
                        suggestions(installed: Set(installed.map(\.name)))
                    }
                    Text("Each model runs Claude Code through Ollama, on this Mac: nothing is sent to Anthropic, "
                         + "and it works offline. Small models are fast but make more mistakes.")
                        .font(Extreme.font(11)).foregroundColor(Extreme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .onAppear { models.watch(true) }
        .onDisappear { models.watch(false) }
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 8) {
            let state = models.ollama
            Circle().fill(state == .notInstalled ? Extreme.dim : state == .stopped ? Extreme.warn : Extreme.live)
                .frame(width: 7, height: 7)
            Text("Ollama").font(Extreme.font(12, weight: .semibold)).foregroundColor(Extreme.text)
            switch state {
            case .notInstalled:
                Text("isn't installed").font(Extreme.font(11)).foregroundColor(Extreme.dim)
                Button("Get Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                    .buttonStyle(ExtremeButtonStyle())
            case .stopped:
                Text("isn't running").font(Extreme.font(11)).foregroundColor(Extreme.warn)
                Button("Start", action: models.startOllama).buttonStyle(ExtremeButtonStyle())
            case .running(let version):
                Text(version.map { "running · \($0)" } ?? "running").font(Extreme.font(11)).foregroundColor(Extreme.muted)
            }
            Spacer()
        }
    }

    private func suggestions(installed: Set<String>) -> some View {
        let memory = Int64(ProcessInfo.processInfo.physicalMemory)
        let list = SuggestedModel.all.filter { !installed.contains($0.name) }
        return VStack(alignment: .leading, spacing: 4) {
            if !list.isEmpty {
                ExtremeSectionLabel("Download")
                ForEach(list) { suggestion in
                    // A model needs roughly its size again in memory, plus room for everything else.
                    let fits = suggestion.bytes * 2 < memory
                    HStack(spacing: 10) {
                        Text(suggestion.name).font(Extreme.mono(12)).foregroundColor(fits ? Extreme.text : Extreme.dim)
                        Text("\(suggestion.size) · \(suggestion.note)").font(Extreme.font(11)).foregroundColor(Extreme.dim)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Download") { models.pull(suggestion.name) }
                            .buttonStyle(ExtremeButtonStyle())
                            .help(fits ? "ollama pull, in a new tab" : "Probably too big for this Mac's memory")
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

private struct LocalModelWindowRow: View {
    let item: LocalModel
    @ObservedObject private var models = LocalModelsModel.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(item.name).font(Extreme.mono(12)).foregroundColor(Extreme.text).lineLimit(1)
            if item.loaded {
                Text("LOADED").font(Extreme.font(9, weight: .bold)).foregroundColor(Extreme.ink)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Extreme.live))
            }
            Text(item.detail).font(Extreme.font(11)).foregroundColor(Extreme.dim).lineLimit(1)
            Spacer(minLength: 8)
            if models.busy.contains(item.id) {
                ProgressView().controlSize(.small)
            } else {
                if item.loaded {
                    Button("Unload") { models.unload(item) }.buttonStyle(ExtremeButtonStyle()).help("Free its memory now")
                }
                Button("Open") {
                    guard let owner = LocalModelsWindow.frontTerminal else { return }
                    LocalModelSessions.open(item.name, from: owner)
                    owner.window?.makeKeyAndOrderFront(nil)
                }
                .buttonStyle(ExtremeButtonStyle(prominent: true))
                .help("Claude Code on \(item.name): below the chat in front, or in a new tab")
            }
        }
        .padding(.vertical, 3)
    }
}

/// The sidebar's Local models section: Ollama's models, to click open or drag under a chat.
/// Takes no room when Ollama has none.
struct LocalModelsSidebarSection: View {
    let owner: TerminalController
    @ObservedObject private var models = LocalModelsModel.shared
    @AppStorage("LocalModelsSectionCollapsed") private var collapsed = false

    var body: some View {
        let list = models.models.filter { $0.host == .ollama }
        VStack(alignment: .leading, spacing: 4) {
            if !list.isEmpty {
                Rectangle().fill(Extreme.line).frame(height: 1).padding(.bottom, 4)
                header(count: list.count)
                if !collapsed {
                    ForEach(list) { LocalModelSidebarRow(item: $0, owner: owner) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, list.isEmpty ? 0 : 6)
        // Stays mounted (empty) so it appears when a model is downloaded.
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
        .onAppear { models.watch(true) }
        .onDisappear { models.watch(false) }
        .animation(.easeOut(duration: 0.18), value: list.map(\.id))
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 6) {
            Button { collapsed.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold)).foregroundColor(Extreme.dim).frame(width: 8)
                    Text("LOCAL MODELS").font(Extreme.font(10.5, weight: .semibold)).kerning(1.1).foregroundColor(Extreme.muted)
                    Text("\(count)").font(Extreme.font(10)).foregroundColor(Extreme.dim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Extreme.line.opacity(0.7)).frame(height: 1)
            Button { LocalModelsWindow.show() } label: {
                Image(systemName: "arrow.up.right.square").font(.system(size: 10)).foregroundColor(Extreme.dim)
            }
            .buttonStyle(.plain)
            .help("Local Models: download, unload and open")
        }
        .padding(.horizontal, 4)
    }
}

private struct LocalModelSidebarRow: View {
    let item: LocalModel
    let owner: TerminalController
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(item.loaded ? Extreme.live : Extreme.dim)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(Extreme.mono(11.5))
                    .foregroundColor(Extreme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.loaded ? "Loaded" + (item.memory.map { " · " + Housekeeping.bytes($0) } ?? "") : item.detail)
                    .font(Extreme.font(9.5))
                    .foregroundColor(item.loaded ? Extreme.live.opacity(0.85) : Extreme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Extreme.dim)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Extreme.raised : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { LocalModelSessions.open(item.name, from: owner) }
        .onDrag {
            // Only our own type, so the terminal never pastes it as text.
            let provider = NSItemProvider()
            let name = item.name
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tellurionLocalModel.identifier, visibility: .ownProcess) { done in
                done(Data(name.utf8), nil)
                return nil
            }
            return provider
        }
        .help("Click to open Claude Code on \(item.name) below the chat in front (or in a new tab).\n"
              + "Drag it onto a chat to open it underneath that one.")
    }
}
#endif
