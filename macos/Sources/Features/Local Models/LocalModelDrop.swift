#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A local model dropped on a terminal pane opens below it, in the pane's folder.
struct LocalModelDropDelegate: DropDelegate {
    @Binding var over: Bool
    let surface: Ghostty.SurfaceView

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.tellurionLocalModel])
    }

    func dropEntered(info: DropInfo) { over = true }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func dropExited(info: DropInfo) { over = false }

    func performDrop(info: DropInfo) -> Bool {
        over = false
        guard let provider = info.itemProviders(for: [.tellurionLocalModel]).first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.tellurionLocalModel.identifier) { [weak surface] data, _ in
            guard let data, let dragged = String(bytes: data, encoding: .utf8), !dragged.isEmpty else { return }
            DispatchQueue.main.async {
                guard let surface, let controller = surface.window?.windowController as? BaseTerminalController else { return }
                // "<host>\t<name>", as the sidebar row wrote it.
                let parts = dragged.split(separator: "\t", maxSplits: 1).map(String.init)
                let host = parts.count == 2 ? LocalModel.Host(rawValue: parts[0]) ?? .ollama : .ollama
                let name = parts.last ?? dragged
                let model = LocalModelsModel.shared.models.first { $0.host == host && $0.name == name }
                    ?? LocalModel(host: host, name: name, size: nil, detail: "", loaded: false, memory: nil, gpuShare: nil)
                LocalModelSessions.open(model, below: surface, in: controller)
            }
        }
        return true
    }
}

/// Where the model will open: the bottom half of the pane, labeled.
struct LocalModelDropPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Rectangle().fill(Extreme.gold.opacity(0.16))
                Rectangle().strokeBorder(Extreme.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Label("Open below this chat", systemImage: "rectangle.split.1x2")
                    .font(Extreme.font(12, weight: .semibold))
                    .foregroundColor(Extreme.gold)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
#endif
