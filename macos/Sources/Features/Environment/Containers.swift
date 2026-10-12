#if os(macOS)
import AppKit
import Combine

/// A Docker container (Docker Desktop, OrbStack, Colima: whatever the docker CLI talks to).
struct ContainerEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let image: String
    /// "running", "exited", "paused", "created"…
    let state: String
    /// Docker's own summary: "Up 6 days (healthy)".
    let status: String
    let ports: String
    /// Its Compose (or Supabase CLI) project, which groups it.
    let project: String?
    var cpu: String?
    var memory: String?

    var isRunning: Bool { state == "running" || state == "restarting" }
    var unhealthy: Bool { status.contains("(unhealthy)") }

    /// "0.0.0.0:54322->5432/tcp, [::]:54322->5432/tcp" → [54322].
    var publishedPorts: [Int] {
        var found: [Int] = []
        for part in ports.split(separator: ",") {
            guard let arrow = part.range(of: "->") else { continue }
            let host = part[..<arrow.lowerBound]
            if let port = host.split(separator: ":").last.flatMap({ Int($0) }), !found.contains(port) { found.append(port) }
        }
        return found
    }
}

/// Lists containers and runs the docker commands the Environment window offers.
final class ContainersModel: ObservableObject {
    enum Runtime: Equatable {
        case unknown
        case notInstalled
        /// The CLI is there but nothing answers: Colima, OrbStack or Docker Desktop is stopped.
        case stopped(context: String)
        case running(context: String)
    }

    @Published private(set) var runtime: Runtime = .unknown
    @Published private(set) var containers: [ContainerEntry] = []
    @Published private(set) var busy: Set<String> = []
    @Published var error: String?

    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-extreme.containers", qos: .userInitiated)
    private var timer: Timer?
    private var loading = false

    static var docker: String? {
        ToolPath.find("docker") ?? [NSHomeDirectory() + "/.orbstack/bin/docker",
                                                     "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Projects in the order they first appear, with their containers.
    var groups: [(project: String, containers: [ContainerEntry])] {
        var order: [String] = []
        var byProject: [String: [ContainerEntry]] = [:]
        for container in containers {
            let key = container.project ?? ""
            if byProject[key] == nil { order.append(key) }
            byProject[key, default: []].append(container)
        }
        return order.map { ($0, byProject[$0] ?? []) }
    }

    /// Refreshes every few seconds while the tab is on screen.
    func start() {
        load()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.load() }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func load() {
        guard !loading else { return }
        loading = true
        queue.async { [weak self] in
            let (runtime, containers) = Self.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.runtime = runtime
                if self.containers != containers { self.containers = containers }
            }
        }
    }

    private static func read() -> (Runtime, [ContainerEntry]) {
        guard let docker else { return (.notInstalled, []) }
        let home = NSHomeDirectory()
        let context = ToolPath.run(docker, ["context", "show"], in: home).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let listed = ToolPath.run(docker, ["ps", "-a", "--format", "{{json .}}"], in: home)
        guard listed.ok else { return (.stopped(context: context.isEmpty ? "docker" : context), []) }
        var containers = listed.output.split(separator: "\n").compactMap { line -> ContainerEntry? in
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = json["ID"] as? String else { return nil }
            let labels = (json["Labels"] as? String ?? "").split(separator: ",").reduce(into: [String: String]()) { result, pair in
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { result[kv[0]] = kv[1] }
            }
            return ContainerEntry(id: id, name: json["Names"] as? String ?? id, image: json["Image"] as? String ?? "",
                                  state: json["State"] as? String ?? "", status: json["Status"] as? String ?? "",
                                  ports: json["Ports"] as? String ?? "",
                                  project: labels["com.docker.compose.project"] ?? labels["com.supabase.cli.project"])
        }
        // Live usage, for the running ones only (stats waits on each, so it's a single pass).
        if containers.contains(where: \.isRunning) {
            let stats = ToolPath.run(docker, ["stats", "--no-stream", "--format", "{{json .}}"], in: home)
            for line in stats.output.split(separator: "\n") {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = json["ID"] as? String,
                      let index = containers.firstIndex(where: { id.hasPrefix($0.id) || $0.id.hasPrefix(id) }) else { continue }
                containers[index].cpu = json["CPUPerc"] as? String
                containers[index].memory = (json["MemUsage"] as? String)?.components(separatedBy: " / ").first
            }
        }
        return (.running(context: context.isEmpty ? "docker" : context), containers)
    }

    // MARK: Actions

    func start(_ container: ContainerEntry) { run(["start", container.id], on: container) }
    func stop(_ container: ContainerEntry) { run(["stop", container.id], on: container) }
    func restart(_ container: ContainerEntry) { run(["restart", container.id], on: container) }
    func remove(_ container: ContainerEntry) { run(["rm", "-f", container.id], on: container) }

    /// Logs follow in a new tab, where they can scroll and be searched.
    func showLogs(_ container: ContainerEntry) {
        SetupChecks.openTab(running: "\(Self.docker.map(AgentTools.shellQuote) ?? "docker") logs -f --tail 200 \(AgentTools.shellQuote(container.name))")
    }

    /// A shell inside the container, in a new tab.
    func openShell(_ container: ContainerEntry) {
        let docker = Self.docker.map(AgentTools.shellQuote) ?? "docker"
        SetupChecks.openTab(running: "\(docker) exec -it \(AgentTools.shellQuote(container.name)) sh -c 'command -v bash >/dev/null && exec bash || exec sh'")
    }

    /// Whether Start can do anything: Colima's command, or OrbStack's or Docker Desktop's app.
    var canStartRuntime: Bool {
        guard case .stopped(let context) = runtime else { return false }
        if context.contains("colima") { return ToolPath.find("colima") != nil }
        let app = context.contains("orbstack") ? "/Applications/OrbStack.app" : "/Applications/Docker.app"
        return FileManager.default.fileExists(atPath: app)
    }

    /// Starts whatever runs containers here: Colima in a tab (it prints progress), or the app.
    func startRuntime() {
        guard case .stopped(let context) = runtime else { return }
        if context.contains("colima"), let colima = ToolPath.find("colima") {
            SetupChecks.openTab(running: "\(AgentTools.shellQuote(colima)) start")
        } else if context.contains("orbstack") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/OrbStack.app"))
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
        }
    }

    private func run(_ args: [String], on container: ContainerEntry) {
        guard let docker = Self.docker else { return }
        busy.insert(container.id)
        error = nil
        queue.async { [weak self] in
            let result = ToolPath.run(docker, args, in: NSHomeDirectory())
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy.remove(container.id)
                if !result.ok {
                    let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.error = message.isEmpty ? "docker \(args[0]) failed" : String(message.prefix(300))
                }
                self.load()
            }
        }
    }
}
#endif
