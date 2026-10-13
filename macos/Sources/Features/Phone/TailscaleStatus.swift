#if os(macOS)
import AppKit
import Combine

/// Where the user's Tailscale setup stands, as far as using GhosttyEXTREME from a phone goes.
/// Read from `tailscale status --json`; nothing here changes Tailscale on its own. Each
/// step the setup panel offers runs only when the user presses its button.
struct TailscaleStatus: Equatable {
    enum State: Equatable {
        case notInstalled
        /// Installed, but its app (and so its background service) isn't running.
        case appNotRunning
        /// Logged in, switched off.
        case stopped
        case needsLogin
        /// Connecting, or another state Tailscale reports while it gets going.
        case starting
        case running
    }

    struct Device: Equatable, Identifiable {
        let name: String
        let os: String
        let online: Bool
        var id: String { name + os }
    }

    var state: State = .notInstalled
    /// This Mac's name on the tailnet, e.g. "studio.tail1234.ts.net".
    var dnsName: String?
    var ip: String?
    var magicDNS = false
    /// The tailnet can issue HTTPS certificates (needed for the phone web app to install and
    /// send notifications).
    var httpsEnabled = false
    /// Phones and tablets on the tailnet.
    var phones: [Device] = []
    /// Where to sign in, when Tailscale has one ready.
    var authURL: URL?

    /// Everything the phone needs is in place.
    var isReady: Bool { state == .running && magicDNS && httpsEnabled && !phones.isEmpty }

    /// The sidebar chip's one line.
    var summary: String {
        switch state {
        case .notInstalled: return "set up"
        case .appNotRunning, .stopped: return "Tailscale off"
        case .needsLogin: return "sign in to Tailscale"
        case .starting: return "connecting…"
        case .running:
            if !magicDNS || !httpsEnabled { return "turn on HTTPS" }
            if phones.isEmpty { return "add your phone" }
            let online = phones.filter(\.online)
            return online.isEmpty ? "ready · phone offline" : "ready · \(online[0].name)"
        }
    }
}

final class TailscaleMonitor: ObservableObject {
    static let shared = TailscaleMonitor()

    @Published private(set) var status = TailscaleStatus()
    /// A step is running (the buttons wait for it).
    @Published private(set) var busy = false
    @Published var error: String?

    private let queue = DispatchQueue(label: "com.steventsvik.ghostty-extreme.tailscale", qos: .utility)
    private var timer: Timer?
    private var fastUntil = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    static let appPath = "/Applications/Tailscale.app"
    static let adminDNS = URL(string: "https://login.tailscale.com/admin/dns")!
    static let download = URL(string: "https://tailscale.com/download")!

    /// The `tailscale` command: on PATH (Homebrew or the app's own CLI link), else inside the app.
    /// Run it with `run(_:)`: the app's binary only acts as the CLI when told to.
    static var binary: String? {
        ToolPath.find("tailscale") ?? [appPath + "/Contents/MacOS/Tailscale"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
        schedule()
    }

    /// Checks every minute while the app is active, and every 3 seconds for a while after a
    /// step (or while the setup panel is open), so the panel follows along.
    private func schedule() {
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, NSApp.isActive || Date() < self.fastUntil else { return }
            let fast = Date() < self.fastUntil || AgentToolWindows.isOpen(PhoneSetup.windowID)
            if fast || Int(Date().timeIntervalSince1970) % 60 < 3 { self.refresh() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        queue.async {
            let status = Self.read()
            DispatchQueue.main.async {
                if status != self.status { self.status = status }
            }
        }
    }

    /// Keep checking quickly for the next two minutes (a step is under way elsewhere).
    func watch() {
        fastUntil = Date().addingTimeInterval(120)
        refresh()
    }

    private static func run(_ binary: String, _ args: [String]) -> AgentTools.Result {
        ToolPath.run(binary, args, in: NSHomeDirectory(), environment: ["TAILSCALE_BE_CLI": "1"])
    }

    // MARK: Reading

    private static func read() -> TailscaleStatus {
        var status = TailscaleStatus()
        guard let binary else { return status }
        let result = Self.run(binary, ["status", "--json"])
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any] else {
            // No service to talk to: the app isn't running (or isn't set up yet).
            status.state = .appNotRunning
            return status
        }
        switch json["BackendState"] as? String {
        case "Running": status.state = .running
        case "Stopped": status.state = .stopped
        case "NeedsLogin", "NeedsMachineAuth": status.state = .needsLogin
        default: status.state = .starting
        }
        status.authURL = (json["AuthURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        let me = json["Self"] as? [String: Any] ?? [:]
        status.dnsName = (me["DNSName"] as? String).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.flatMap { $0.isEmpty ? nil : $0 }
        status.ip = (me["TailscaleIPs"] as? [String])?.first { !$0.contains(":") }
        status.magicDNS = (json["CurrentTailnet"] as? [String: Any])?["MagicDNSEnabled"] as? Bool ?? false
        status.httpsEnabled = !((json["CertDomains"] as? [String]) ?? []).isEmpty
        let peers = (json["Peer"] as? [String: [String: Any]] ?? [:]).values
        status.phones = peers
            .filter { ["iOS", "android"].contains($0["OS"] as? String ?? "") }
            .map { peer in
                let host = peer["HostName"] as? String ?? ""
                // iPhones report "localhost" as their host name; the DNS name is the real one.
                let dns = (peer["DNSName"] as? String)?.split(separator: ".").first.map(String.init)
                let name = host.isEmpty || host == "localhost" ? (dns ?? "Phone") : host
                return TailscaleStatus.Device(name: name, os: peer["OS"] as? String ?? "", online: peer["Online"] as? Bool ?? false)
            }
            .sorted { ($0.online ? 0 : 1, $0.name) < ($1.online ? 0 : 1, $1.name) }
        return status
    }

    // MARK: Steps (each runs only from its button)

    /// Installs Tailscale with Homebrew in a new tab, or opens the download page.
    func install() {
        if let brew = ToolPath.find("brew") {
            SetupChecks.openTab(running: "\(AgentTools.shellQuote(brew)) install --cask tailscale && open -a Tailscale")
        } else {
            NSWorkspace.shared.open(Self.download)
        }
        watch()
    }

    /// Opens the Tailscale app, which starts its background service.
    func openApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.appPath))
        watch()
    }

    /// Switches Tailscale on (`tailscale up`). Signing in happens in the browser.
    func connect() {
        guard let binary = Self.binary else { return }
        if status.state == .needsLogin, let url = status.authURL {
            NSWorkspace.shared.open(url)
            watch()
            return
        }
        busy = true
        error = nil
        queue.async {
            // `up` waits for sign-in when it's needed; don't hold the button for that.
            let result = Self.run(binary, ["up", "--timeout=15s"])
            let text = (result.output + "\n" + result.error)
            let login = text.split(whereSeparator: \.isWhitespace).first { $0.hasPrefix("https://login.tailscale.com/") }
            DispatchQueue.main.async {
                self.busy = false
                if let login, let url = URL(string: String(login)) {
                    NSWorkspace.shared.open(url)
                } else if !result.ok, !text.contains("timeout") {
                    self.error = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
                }
                self.watch()
            }
        }
    }

    /// Opens the admin page where MagicDNS and HTTPS certificates are switched on.
    func openHTTPSSettings() {
        NSWorkspace.shared.open(Self.adminDNS)
        watch()
    }
}
#endif
