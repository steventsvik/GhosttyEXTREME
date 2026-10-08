import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // GhosttyEXTREME: its own feed, published with every release and signed with its own
        // key (SUPublicEDKey). Ghostty's feeds would offer official Ghostty, which would replace
        // this app. There's one channel; the `auto-update-channel` setting doesn't apply.
        // Test-only: `GHOSTTY_EXTREME_TEST_FEED=<url>` points a test copy at a local feed.
        ProcessInfo.processInfo.environment["GHOSTTY_EXTREME_TEST_FEED"]
            ?? "https://github.com/steventsvik/GhosttyEXTREME/releases/latest/download/appcast.xml"
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // When the updater is relaunching the application we want to get macOS
        // to invalidate and re-encode all of our restorable state so that when
        // we relaunch it uses it.
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
        // GhosttyEXTREME: keep the windows for this quit and remember what's running in them.
        ResumeAfterUpdate.prepare()
    }
}
