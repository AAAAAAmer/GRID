import AppKit
import Foundation

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run purely as an accessory Menu Bar agent (no Dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // ⌘⌥⌃G re-snaps from anywhere (⌘⌥⌃1…9 per profile are bound by the menu)
        HotKeyManager.shared.registerResnapHotKey {
            WindowManager.shared.resnapCurrent()
        }

        // Setup the Menu Bar UI
        MenuBarController.shared.setup()

        // Listen for screen hardware changes (menu refresh only; profiles are applied manually)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Request Accessibility permissions if not already granted
        WindowManager.shared.ensureAccessibilityPermissions()
        Log.app.info("Native agent initialized successfully.")
    }

    @objc private func screenParametersChanged() {
        Log.app.info("Display topology change detected.")
        MenuBarController.shared.rebuildMenu()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
        Log.app.info("Terminating GRID.")
    }
}
