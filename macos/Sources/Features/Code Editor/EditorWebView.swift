#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import WebKit

/// The web view hosting the VS Code–style editor (macos/EditorWeb, built on Monaco).
///
/// One instance is shared by the whole app and moved into whichever window shows the
/// editor panel. It runs in WebKit's own process and is only created the first time the
/// panel opens, so the terminal pays nothing for it otherwise.
final class EditorWebView: WKWebView {
    static let scheme = "ghostty-editor"

    private let files = EditorFileBridge()
    private(set) var isReady = false
    private var pending: [String] = []

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(EditorAssetHandler(), forURLScheme: Self.scheme)
        super.init(frame: .zero, configuration: configuration)
        configuration.userContentController.addScriptMessageHandler(files, contentWorld: .page, name: "fs")
        files.onReady = { [weak self] in self?.didBecomeReady() }
        uiDelegate = self
        setValue(false, forKey: "drawsBackground")
        load(URLRequest(url: URL(string: "\(Self.scheme)://app/index.html")!))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Commands from the app

    /// The folder shown in the Explorer.
    var currentFolder: String? { files.root }

    func openFolder(_ path: String) {
        let root = (path as NSString).standardizingPath
        guard root != files.root else { return }
        files.root = root
        files.allowedRoots.insert(root)
        let branch = Self.branch(of: root) ?? ""
        run("app.openFolder(\(Self.js(root)), \(Self.js((root as NSString).lastPathComponent)), \(Self.js(branch)))")
    }

    func openFile(_ path: String, line: Int? = nil) {
        if files.root == nil { openFolder((path as NSString).deletingLastPathComponent) }
        run("app.openFile(\(Self.js(path)), \(line.map(String.init) ?? "undefined"))")
    }

    func focusEditor() {
        window?.makeFirstResponder(self)
        run("app.focus()")
    }

    private func run(_ script: String) {
        if isReady { evaluateJavaScript(script) } else { pending.append(script) }
    }

    private func didBecomeReady() {
        isReady = true
        pending.forEach { evaluateJavaScript($0) }
        pending.removeAll()
    }

    // MARK: Keyboard

    /// Command-key shortcuts normally go to the app's menus first (⌘W would close the
    /// terminal tab). While the editor has focus, send them to the page instead so VS Code
    /// shortcuts work. App-level shortcuts and the clipboard (handled through the Edit
    /// menu, which WebKit supports) still go to the app.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let responder = window?.firstResponder as? NSView, responder === self || responder.isDescendant(of: self),
              event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let appLevel: Set<String> = ["q", "h", "t", "n", ",", "`", "c", "v", "x", "a", "m"]
        if flags.contains(.control) || appLevel.contains(key) {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    /// Streams the agent timeline to the page. Files the agent touches become readable
    /// so follow mode can open them even outside the Explorer's folder.
    func sendAgentItems(_ items: [AgentFeed.Item], reset: Bool) {
        for item in items {
            if let path = item["path"] as? String, path.hasPrefix("/") {
                files.allowedFiles.insert((path as NSString).standardizingPath)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8) else { return }
        run("app.agentItems(\(json), \(reset))")
    }

    func sendAgentStatus(_ status: [String: Any]?) {
        guard let status else { run("app.agentStatus(null)"); return }
        guard let data = try? JSONSerialization.data(withJSONObject: status),
              let json = String(data: data, encoding: .utf8) else { return }
        run("app.agentStatus(\(json))")
    }

    /// Applies the terminal's colors and font (see `EditorTheme`).
    func setTheme(_ json: String) {
        run("app.setTheme(\(json))")
    }

    // MARK: Helpers

    static func branch(of root: String) -> String? {
        guard let repo = VerticalTabsGit.repoRoot(containing: root),
              let head = try? String(contentsOfFile: repo.gitDir + "/HEAD", encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("ref: refs/heads/") ? String(trimmed.dropFirst(16)) : String(trimmed.prefix(7))
    }

    static func js(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}

// MARK: - Alerts and confirms from the page

extension EditorWebView: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        let parts = message.components(separatedBy: "\n\n")
        alert.messageText = parts.first ?? message
        if parts.count > 1 { alert.informativeText = "Your changes will be lost if you don't save them." }
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

// MARK: - Serving the bundled page

/// Serves macos/EditorWeb from the app bundle under ghostty-editor://app/. A custom
/// scheme (rather than file://) lets Monaco start its web workers.
private final class EditorAssetHandler: NSObject, WKURLSchemeHandler {
    private let base = Bundle.main.resourceURL!.appendingPathComponent("EditorWeb")

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let relative = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let file = base.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": String(data.count)])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - File access for the page

/// Answers the page's `fs` requests. Access is limited to the open workspace folder.
private final class EditorFileBridge: NSObject, WKScriptMessageHandlerWithReply {
    var root: String?
    /// Every folder shown this session. Open tabs from earlier folders stay editable.
    var allowedRoots: Set<String> = []
    /// Files an agent touched, which follow mode may open.
    var allowedFiles: Set<String> = []
    var onReady: (() -> Void)?

    private let maxFileSize = 8 * 1024 * 1024
    private let hidden: Set<String> = [".git", ".DS_Store", "node_modules", ".zig-cache", "zig-out", ".build", "build", "DerivedData"]

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "bad request")
            return
        }
        if op == "log" {
            let line = "[editor] \(body["message"] ?? "")"
            NSLog("%@", line)
            if let path = ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_LOG"],
               let handle = FileHandle(forWritingAtPath: path) ?? {
                   FileManager.default.createFile(atPath: path, contents: nil)
                   return FileHandle(forWritingAtPath: path)
               }() {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8)!)
                handle.closeFile()
            }
            replyHandler(true, nil)
            return
        }
        if op == "ready" {
            onReady?()
            replyHandler(true, nil)
            return
        }
        // File work happens off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = handle(op, body)
            DispatchQueue.main.async { replyHandler(result, nil) }
        }
    }

    private func handle(_ op: String, _ body: [String: Any]) -> Any {
        switch op {
        case "list":
            guard let path = allowed(body["path"]) else { return [] as [Any] }
            return list(path)
        case "read":
            guard let path = allowed(body["path"]) else { return ["error": "Outside the open folder"] }
            return read(path)
        case "write":
            guard let path = allowed(body["path"]), let content = body["content"] as? String else {
                return ["error": "Outside the open folder"]
            }
            return write(path, content)
        case "stat":
            let paths = (body["paths"] as? [Any] ?? []).compactMap(allowed)
            var result: [String: Double] = [:]
            for path in paths { result[path] = mtime(path) }
            return result
        case "files":
            return allFiles()
        default:
            return ["error": "unknown op \(op)"]
        }
    }

    private func allowed(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let path = (raw as NSString).standardizingPath
        if allowedFiles.contains(path) { return path }
        let roots = allowedRoots.union(root.map { [$0] } ?? [])
        return roots.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") } ? path : nil
    }

    private func list(_ path: String) -> [[String: Any]] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [[String: Any]] = []
        for name in names where !hidden.contains(name) {
            let full = path + "/" + name
            var isDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &isDir)
            entries.append(["name": name, "path": full, "isDir": isDir.boolValue])
        }
        return entries.sorted {
            let (a, b) = ($0["isDir"] as! Bool, $1["isDir"] as! Bool)
            if a != b { return a }
            return ($0["name"] as! String).localizedStandardCompare($1["name"] as! String) == .orderedAscending
        }
    }

    private func read(_ path: String) -> [String: Any] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return ["error": "Can't read \(path)"]
        }
        if (attributes[.size] as? Int ?? 0) > maxFileSize {
            return ["error": "\((path as NSString).lastPathComponent) is too large to open in the editor."]
        }
        guard let data = FileManager.default.contents(atPath: path) else { return ["error": "Can't read \(path)"] }
        guard !data.prefix(8000).contains(0), let text = String(data: data, encoding: .utf8) else {
            return ["error": "\((path as NSString).lastPathComponent) is a binary file."]
        }
        return ["content": text, "mtime": mtime(path) ?? 0]
    }

    private func write(_ path: String, _ content: String) -> [String: Any] {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return ["mtime": mtime(path) ?? 0]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private func mtime(_ path: String) -> Double? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        return date.timeIntervalSince1970
    }

    /// Relative paths for quick open. Uses git (respects .gitignore) when possible.
    private func allFiles() -> [String] {
        guard let root else { return [] }
        if VerticalTabsGit.repoRoot(containing: root) != nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) {
                    return output.split(separator: "\n").prefix(50_000).map(String.init)
                }
            }
        }
        var results: [String] = []
        let enumerator = FileManager.default.enumerator(atPath: root)
        while let item = enumerator?.nextObject() as? String, results.count < 50_000 {
            let name = (item as NSString).lastPathComponent
            if hidden.contains(name) { enumerator?.skipDescendants(); continue }
            if let type = enumerator?.fileAttributes?[.type] as? FileAttributeType, type == .typeRegular {
                results.append(item)
            }
        }
        return results
    }
}
#endif
