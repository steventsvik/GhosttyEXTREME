#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Claude Code running on a model on this Mac, served by Ollama.
///
/// Opening a model types `tellurion local <model>` into a shell: the same settings
/// `ollama launch claude` uses, so Claude Code talks to Ollama instead of Anthropic. Its
/// hooks report as usual, so the pane gets the sidebar status, alerts, undo and review of
/// any Claude Code session; the sidebar names the model instead of Claude Code.
@MainActor
enum LocalModelSessions {
    /// Panes Tellurion opened on a local model, until their session ends. Only touched on
    /// the main thread (agent events arrive there too).
    nonisolated(unsafe) private static let models = NSMapTable<Ghostty.SurfaceView, NSString>.weakToStrongObjects()

    nonisolated static func model(on surface: Ghostty.SurfaceView) -> String? {
        models.object(forKey: surface) as String?
    }

    nonisolated static func ended(on surface: Ghostty.SurfaceView) {
        models.removeObject(forKey: surface)
    }

    /// What's typed into the shell.
    static func command(_ model: String) -> String {
        let cli = HookInstaller.binFolder.appendingPathComponent("tellurion").path
        return "\(AgentTools.shellQuote(cli)) local \(AgentTools.shellQuote(model))"
    }

    /// Opens it below the chat in front, or in a tab of its own when there's no chat there.
    static func open(_ model: String, from owner: TerminalController) {
        if let surface = owner.focusedSurface, VerticalTabsAgents.shared.info(for: surface) != nil {
            open(model, below: surface, in: owner)
        } else {
            openTab(model, from: owner)
        }
    }

    /// Splits the pane and opens it underneath, in the pane's folder.
    static func open(_ model: String, below surface: Ghostty.SurfaceView, in controller: BaseTerminalController) {
        guard prepare() else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = surface.pwd
        config.initialInput = command(model) + "\n"
        guard let pane = controller.newSplit(at: surface, direction: .down, baseConfig: config) else { return }
        models.setObject(model as NSString, forKey: pane)
    }

    static func openTab(_ model: String, from owner: TerminalController) {
        guard prepare() else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = owner.focusedSurface?.pwd
        config.initialInput = command(model) + "\n"
        guard let controller = TerminalController.newTab(owner.ghostty, from: owner.window, withBaseConfig: config),
              let pane = controller.surfaceTree.root?.leftmostLeaf() else { return }
        models.setObject(model as NSString, forKey: pane)
    }

    /// The `tellurion` command has to be installed (and current) to launch it.
    private static func prepare() -> Bool {
        guard HookInstaller.filesState() != .current else { return true }
        do {
            try HookInstaller.installFiles()
            return true
        } catch {
            LocalModelsModel.shared.error = error.localizedDescription
            return false
        }
    }
}

extension UTType {
    /// A local model's name, dragged from the sidebar onto a terminal pane.
    static let tellurionLocalModel = UTType(exportedAs: "com.steventsvik.tellurion.localModel")
}
#endif
