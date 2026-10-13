#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The phone setup window: Tailscale step by step, then the devices that can reach this Mac.
enum PhoneSetup {
    static let windowID = "phone"

    static func show() {
        guard ExtremeSettings.isOn(.phone) else { return }
        TailscaleMonitor.shared.watch()
        AgentToolWindows.show(id: windowID, title: "Phone", size: NSSize(width: 560, height: 600)) {
            PhoneSetupView()
        }
    }
}

// MARK: - Sidebar chip

/// Bottom of the sidebar: one line saying whether the phone can reach this Mac.
struct PhoneStatusChip: View {
    @ObservedObject private var monitor = TailscaleMonitor.shared

    var body: some View {
        let status = monitor.status
        Button(action: PhoneSetup.show) {
            HStack(spacing: 7) {
                PixelIconView(icon: .phone, color: color(status), pixel: 1.3)
                Text("Phone")
                    .font(Extreme.font(11.5, weight: .semibold))
                    .foregroundColor(Extreme.text)
                Text(status.summary)
                    .font(Extreme.font(10.5))
                    .foregroundColor(status.isReady ? Extreme.muted : color(status))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(color(status)).frame(width: 6, height: 6)
                    .shadow(color: color(status).opacity(status.isReady ? 0.7 : 0), radius: 3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Use your terminal from your phone over Tailscale. Click to set up or see devices.")
    }

    private func color(_ status: TailscaleStatus) -> Color {
        if status.isReady { return Extreme.live }
        switch status.state {
        case .notInstalled, .appNotRunning, .stopped: return Extreme.dim
        default: return Extreme.gold
        }
    }
}

// MARK: - Setup window

private struct PhoneSetupView: View {
    @ObservedObject private var monitor = TailscaleMonitor.shared

    private enum StepState { case done, current, later }

    var body: some View {
        let status = monitor.status
        VStack(alignment: .leading, spacing: 0) {
            ExtremeWindowTitle(icon: .phone, title: "Phone",
                               subtitle: "Use this Mac's terminal from your phone, over your own private Tailscale network")
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 16)
            Rectangle().fill(Extreme.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Install Tailscale", state: installState(status),
                         detail: "Free for personal use. It connects your Mac and phone privately, on Wi-Fi or cellular.") {
                        Button(ToolPath.find("brew") == nil ? "Download…" : "Install with Homebrew") { monitor.install() }
                            .buttonStyle(ExtremeButtonStyle(prominent: true))
                    }
                    step(2, "Turn it on and sign in", state: connectState(status), detail: connectDetail(status)) {
                        if status.state == .appNotRunning {
                            Button("Open Tailscale") { monitor.openApp() }.buttonStyle(ExtremeButtonStyle(prominent: true))
                        } else {
                            Button(status.state == .needsLogin ? "Sign in…" : "Turn on") { monitor.connect() }
                                .buttonStyle(ExtremeButtonStyle(prominent: true))
                                .disabled(monitor.busy)
                        }
                    }
                    step(3, "Turn on HTTPS for your tailnet", state: httpsState(status),
                         detail: "One switch on Tailscale's DNS page: MagicDNS and HTTPS Certificates. The phone app needs it to install to your home screen and notify you. This page notices when it's on.") {
                        Button("Open DNS settings…") { monitor.openHTTPSSettings() }.buttonStyle(ExtremeButtonStyle(prominent: true))
                    }
                    step(4, "Add your phone", state: phoneState(status),
                         detail: "Install Tailscale on your phone and sign in with the same account.") {
                        HStack(alignment: .center, spacing: 14) {
                            QRCodeView(text: "https://tailscale.com/download", size: 104)
                            Text("Scan with your phone's camera")
                                .font(Extreme.font(11))
                                .foregroundColor(Extreme.muted)
                        }
                    }
                    if let error = monitor.error {
                        Text(error)
                            .font(Extreme.font(11))
                            .foregroundColor(Extreme.danger)
                            .textSelection(.enabled)
                    }
                    if status.state == .running { devices(status) }
                    Text("GhosttyEXTREME only uses Tailscale inside your own tailnet. It never turns on Funnel, which would put your terminal on the public internet.")
                        .font(Extreme.font(10.5))
                        .foregroundColor(Extreme.dim)
                        .padding(.top, 4)
                }
                .padding(22)
            }
        }
        .frame(minWidth: 480, minHeight: 480)
    }

    // MARK: Steps

    private func installState(_ s: TailscaleStatus) -> StepState { s.state == .notInstalled ? .current : .done }

    private func connectState(_ s: TailscaleStatus) -> StepState {
        switch s.state {
        case .notInstalled: return .later
        case .running: return .done
        default: return .current
        }
    }

    private func connectDetail(_ s: TailscaleStatus) -> String {
        switch s.state {
        case .appNotRunning: return "Tailscale is installed but not running."
        case .stopped: return "Tailscale is switched off."
        case .needsLogin: return "Sign in in your browser; this page continues by itself."
        case .starting: return "Connecting…"
        default: return s.dnsName.map { "Connected as \($0)" } ?? "Connected"
        }
    }

    private func httpsState(_ s: TailscaleStatus) -> StepState {
        guard s.state == .running else { return .later }
        return s.magicDNS && s.httpsEnabled ? .done : .current
    }

    private func phoneState(_ s: TailscaleStatus) -> StepState {
        guard s.state == .running else { return .later }
        return s.phones.isEmpty ? .current : .done
    }

    private func step<Action: View>(_ number: Int, _ title: String, state: StepState, detail: String,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(state == .done ? Extreme.live.opacity(0.18) : state == .current ? Extreme.gold.opacity(0.18) : Extreme.raised)
                Circle()
                    .strokeBorder(state == .done ? Extreme.live : state == .current ? Extreme.gold : Extreme.line, lineWidth: 1)
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(Extreme.live)
                } else {
                    Text("\(number)").font(Extreme.font(11, weight: .semibold))
                        .foregroundColor(state == .current ? Extreme.gold : Extreme.dim)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Extreme.font(13, weight: .semibold))
                    .foregroundColor(state == .later ? Extreme.dim : Extreme.text)
                if state != .done || number == 2 {
                    Text(detail)
                        .font(Extreme.font(11))
                        .foregroundColor(state == .later ? Extreme.dim : Extreme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state == .current { action().padding(.top, 2) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(state == .current ? Extreme.panel : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(state == .current ? Extreme.gold.opacity(0.35) : Extreme.line.opacity(0.6)))
    }

    // MARK: Devices

    private func devices(_ s: TailscaleStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ExtremeSectionLabel("On your tailnet")
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer").foregroundColor(Extreme.gold)
                Text("This Mac").font(Extreme.font(12, weight: .semibold)).foregroundColor(Extreme.text)
                Text(s.dnsName ?? s.ip ?? "").font(Extreme.font(11)).foregroundColor(Extreme.muted)
                    .textSelection(.enabled).lineLimit(1)
            }
            ForEach(s.phones) { phone in
                HStack(spacing: 8) {
                    Image(systemName: "iphone").foregroundColor(phone.online ? Extreme.live : Extreme.dim)
                    Text(phone.name).font(Extreme.font(12, weight: .semibold)).foregroundColor(Extreme.text)
                    Text(phone.online ? "online" : "offline").font(Extreme.font(11))
                        .foregroundColor(phone.online ? Extreme.live : Extreme.dim)
                }
            }
            if s.isReady {
                Text("Ready. Pairing your phone with GhosttyEXTREME comes next.")
                    .font(Extreme.font(11))
                    .foregroundColor(Extreme.muted)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 6)
    }
}

/// A QR code for `text`, drawn crisp at any size.
struct QRCodeView: View {
    let text: String
    let size: CGFloat

    var body: some View {
        if let image = Self.image(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        }
    }

    static func image(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
#endif
