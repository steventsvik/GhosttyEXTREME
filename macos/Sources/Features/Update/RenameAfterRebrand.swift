#if os(macOS)
import AppKit
import CoreServices

/// Copies installed before the rename keep their file name when they update (the updater
/// installs over the same path), so Finder, Spotlight and Launchpad would still say
/// GhosttyEXTREME. On a normal quit the app renames its own bundle to Tellurion.app.
/// Never while an update is being installed: the installer is about to write to this path.
enum RenameAfterRebrand {
    private static let oldName = "GhosttyEXTREME.app"
    private static let newName = "Tellurion.app"

    /// Set by the updater's delegate once an update is going to be installed.
    static var updatePending = false

    static func renameIfNeeded() {
        guard !updatePending else { return }
        let bundle = Bundle.main.bundleURL
        guard bundle.lastPathComponent == oldName else { return }
        let target = bundle.deletingLastPathComponent().appendingPathComponent(newName)
        // Another copy already has the new name: leave both alone.
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.moveItem(at: bundle, to: target)
            LSRegisterURL(target as CFURL, true)
        } catch {
            // A read-only or protected location: keep the old name.
        }
    }
}
#endif
