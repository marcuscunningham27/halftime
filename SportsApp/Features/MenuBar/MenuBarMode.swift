import AppKit

/// "Close to Menu": with the main window closed, Sports drops its Dock icon and lives in the menu bar,
/// still polling and sending alerts. Opening the window brings the Dock icon back.
enum MenuBarMode {
    static let closeToMenuKey = "closeToMenu"

    @MainActor static func windowOpened() {
        NSApp.setActivationPolicy(.regular)
    }

    @MainActor static func windowClosed() {
        guard UserDefaults.standard.bool(forKey: closeToMenuKey) else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
