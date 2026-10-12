#if os(macOS)
import Foundation

/// What a folder sets up for whoever works in it: the tool versions it asks for (mise,
/// asdf, .nvmrc and friends), whether they're installed, and the environment variables
/// mise and direnv add. Only variable names are ever read or shown, never values.
struct FolderEnvironment: Equatable {
    struct Tool: Identifiable, Equatable {
        let name: String
        /// What the folder asks for: "20", "3.12", "lts".
        let requested: String
        /// What mise resolves that to, when mise manages it.
        let resolved: String?
        /// nil when unknown (a version file without mise).
        let installed: Bool?
        /// The file that asks for it.
        let source: String
        /// What the terminal runs without mise: `node --version` on the login PATH.
        var onPath: String?
        var id: String { name + source }

        /// The terminal's own copy differs from what the folder asks for.
        var mismatch: Bool {
            guard let onPath, !requested.isEmpty, requested.first?.isNumber == true else { return false }
            let have = onPath.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            return !(have == requested || have.hasPrefix(requested + "."))
        }
    }

    struct Variable: Identifiable, Equatable {
        let name: String
        let source: String
        var id: String { source + name }
    }

    enum Mise: Equatable {
        case notInstalled
        /// Installed; this folder has no mise config.
        case unused
        case active
        /// mise won't read these config files until they're trusted.
        case untrusted([String])
        case failed(String)
    }

    enum Direnv: Equatable {
        case notInstalled
        case unused
        case allowed(String)
        /// Changed or new since it was last allowed, so direnv won't load it.
        case notAllowed(String)
        case denied(String)
    }

    let folder: String
    var tools: [Tool] = []
    var variables: [Variable] = []
    var mise: Mise = .notInstalled
    /// ~/.zshrc (or similar) runs `mise activate`, so terminals switch versions per folder.
    var miseActivated = false
    var direnv: Direnv = .notInstalled
    var direnvHooked = false

    /// Nothing here sets anything up.
    var isEmpty: Bool {
        guard tools.isEmpty, variables.isEmpty, direnvFile == nil else { return false }
        switch mise {
        case .untrusted, .failed: return false
        default: return true
        }
    }

    var direnvFile: String? {
        switch direnv {
        case .allowed(let path), .notAllowed(let path), .denied(let path): return path
        default: return nil
        }
    }
}

enum FolderEnvironmentProbe {
    /// Version files other tools read, and the tool each one names.
    static let versionFiles: [(file: String, tool: String)] = [
        (".nvmrc", "node"), (".node-version", "node"), (".python-version", "python"),
        (".ruby-version", "ruby"), (".go-version", "go"), (".java-version", "java"),
        (".bun-version", "bun"), (".terraform-version", "terraform"),
    ]

    /// The command that prints each tool's version.
    private static let versionCommand: [String: (String, [String])] = [
        "node": ("node", ["--version"]), "python": ("python3", ["--version"]), "ruby": ("ruby", ["--version"]),
        "go": ("go", ["version"]), "bun": ("bun", ["--version"]), "deno": ("deno", ["--version"]),
        "java": ("java", ["-version"]), "rust": ("rustc", ["--version"]), "terraform": ("terraform", ["version"]),
        "pnpm": ("pnpm", ["--version"]), "yarn": ("yarn", ["--version"]), "uv": ("uv", ["--version"]),
    ]

    /// Reads everything about `folder`. Runs mise, direnv and each tool once; call off the main thread.
    static func probe(_ folder: String) -> FolderEnvironment {
        var env = FolderEnvironment(folder: folder)
        let shellRC = ["/.zshrc", "/.zprofile", "/.bashrc", "/.bash_profile", "/.config/fish/config.fish"]
            .compactMap { try? String(contentsOfFile: NSHomeDirectory() + $0, encoding: .utf8) }.joined(separator: "\n")

        // mise
        if let mise = ToolPath.find("mise") {
            env.miseActivated = shellRC.contains("mise activate")
            let listed = ToolPath.run(mise, ["ls", "--current", "--json"], in: folder)
            if listed.ok, let json = try? JSONSerialization.jsonObject(with: Data(listed.output.utf8)) as? [String: Any] {
                for (name, value) in json.sorted(by: { $0.key < $1.key }) {
                    for entry in value as? [[String: Any]] ?? [] {
                        let source = (entry["source"] as? [String: Any])?["path"] as? String ?? ""
                        env.tools.append(.init(name: name, requested: entry["requested_version"] as? String ?? "",
                                               resolved: entry["version"] as? String, installed: entry["installed"] as? Bool,
                                               source: display(source, in: folder)))
                    }
                }
                env.mise = env.tools.isEmpty ? .unused : .active
                if env.mise == .active {
                    let vars = ToolPath.run(mise, ["env", "--json"], in: folder)
                    if let object = try? JSONSerialization.jsonObject(with: Data(vars.output.utf8)) as? [String: Any] {
                        // Names only: values can be secrets.
                        env.variables += object.keys.filter { $0 != "PATH" && !$0.hasPrefix("MISE_") }.sorted()
                            .map { .init(name: $0, source: "mise") }
                    }
                }
            } else {
                let message = listed.error
                if message.contains("not trusted") {
                    let files = message.split(separator: "\n").compactMap { line -> String? in
                        guard let range = line.range(of: "Config files in "), let end = line.range(of: " are not trusted") else { return nil }
                        return String(line[range.upperBound..<end.lowerBound])
                    }
                    env.mise = .untrusted(files.isEmpty ? [folder] : files)
                } else {
                    let line = message.split(separator: "\n").first { $0.contains("ERROR") }.map(String.init) ?? message
                    env.mise = message.isEmpty ? .unused : .failed(line.replacingOccurrences(of: "mise ERROR ", with: ""))
                }
            }
        }

        // Version files mise didn't already account for.
        for (file, tool) in versionFiles where !env.tools.contains(where: { $0.name == tool }) {
            guard let path = nearest(file, from: folder),
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let requested = text.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            env.tools.append(.init(name: tool, requested: requested.replacingOccurrences(of: "v", with: ""), resolved: nil,
                                   installed: nil, source: display(path, in: folder)))
        }
        if env.mise != .active, let path = nearest(".tool-versions", from: folder),
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ").map(String.init)
                guard parts.count >= 2, !parts[0].hasPrefix("#"), !env.tools.contains(where: { $0.name == parts[0] }) else { continue }
                env.tools.append(.init(name: parts[0], requested: parts[1], resolved: nil, installed: nil,
                                       source: display(path, in: folder)))
            }
        }
        // What the terminal runs when nothing switches versions for it.
        if !(env.mise == .active && env.miseActivated) {
            for index in env.tools.indices {
                guard let (command, args) = versionCommand[env.tools[index].name],
                      let binary = SetupChecks.locate(command) else { continue }
                let result = ToolPath.run(binary, args, in: folder)
                env.tools[index].onPath = version(in: result.output + result.error)
            }
        }

        // direnv
        if let direnv = ToolPath.find("direnv") {
            env.direnvHooked = shellRC.contains("direnv hook")
            let status = ToolPath.run(direnv, ["status", "--json"], in: folder)
            if let json = try? JSONSerialization.jsonObject(with: Data(status.output.utf8)) as? [String: Any],
               let found = (json["state"] as? [String: Any])?["foundRC"] as? [String: Any],
               let path = found["path"] as? String {
                switch found["allowed"] as? Int {
                case 0: env.direnv = .allowed(path)
                case 2: env.direnv = .denied(path)
                default: env.direnv = .notAllowed(path)
                }
                // Read, never run: the exports' names, straight from the file.
                if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                    env.variables += exportedNames(text).map { .init(name: $0, source: display(path, in: folder)) }
                }
            } else {
                env.direnv = .unused
            }
        } else if let path = nearest(".envrc", from: folder) {
            env.direnv = .notAllowed(path)
        }
        return env
    }

    /// `export NAME=…` lines in an .envrc.
    static func exportedNames(_ text: String) -> [String] {
        var names: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("export ") else { continue }
            let name = trimmed.dropFirst(7).prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if !name.isEmpty, !names.contains(String(name)) { names.append(String(name)) }
        }
        return names
    }

    /// "v22.3.0" out of "Python 3.12.1", "go version go1.22.4 darwin/arm64", "v22.3.0".
    static func version(in output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"v?\d+\.\d+(\.\d+)?"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else { return nil }
        return String(output[range]).replacingOccurrences(of: "v", with: "")
    }

    /// `file` in `folder` or the closest folder above it (up to the home folder).
    static func nearest(_ file: String, from folder: String) -> String? {
        // Plain path arithmetic, so the result starts with `folder` as given (no /private/tmp → /tmp).
        var dir = folder
        let home = NSHomeDirectory()
        while true {
            let candidate = (dir as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || dir == home || parent.isEmpty { return nil }
            dir = parent
        }
    }

    /// A path relative to the folder ("mise.toml", "../.envrc"), or with ~ for the home folder.
    static func display(_ path: String, in folder: String) -> String {
        if path.hasPrefix(folder + "/") { return String(path.dropFirst(folder.count + 1)) }
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
#endif
