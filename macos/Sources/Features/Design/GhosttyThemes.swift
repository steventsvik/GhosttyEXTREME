#if os(macOS)
import AppKit

/// Ghostty's built-in themes (and any in the user's themes folder), read from disk.
enum GhosttyThemes {
    /// Where themes live, the user's folder first so it can shadow a built-in name.
    static var folders: [URL] {
        var urls: [URL] = []
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config", isDirectory: true)
        urls.append(xdg.appendingPathComponent("ghostty/themes", isDirectory: true))
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent("ghostty/themes", isDirectory: true))
        }
        return urls
    }

    /// Every theme name, sorted, read once.
    static let names: [String] = {
        var seen = Set<String>()
        var names: [String] = []
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in items where !url.lastPathComponent.hasPrefix(".") && seen.insert(url.lastPathComponent).inserted {
                names.append(url.lastPathComponent)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    private static var cache: [String: TerminalColors] = [:]

    /// The colors of the theme called `name`, if it exists and parses.
    static func colors(named name: String) -> TerminalColors? {
        if let hit = cache[name] { return hit }
        for folder in folders {
            let url = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8), let colors = TerminalColors(themeText: text) else { continue }
            cache[name] = colors
            return colors
        }
        return nil
    }

    /// Monospaced font families installed on this Mac, for the font picker.
    static let monospacedFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) ?? manager.font(withFamily: family, traits: [], weight: 5, size: 12) else { return false }
            return font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
}
#endif
