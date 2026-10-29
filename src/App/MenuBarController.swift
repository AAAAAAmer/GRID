import AppKit
import Foundation
import GRIDCore
import ServiceManagement

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    override private init() {
        super.init()
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        // Load custom logo icon from the app bundle
        if let iconUrl = Bundle.main.url(forResource: "menubar_icon", withExtension: "png") ??
                         Bundle.main.url(forResource: "logo", withExtension: "png"),
           let img = NSImage(contentsOf: iconUrl) {
            img.size = NSSize(width: 18, height: 18)
            button.image = img
            button.imagePosition = .imageLeft
            button.title = " GRID"
        } else {
            button.title = "⊞ GRID"
        }

        button.toolTip = "GRID: Workspace & Window Manager"

        menu.delegate = self
        statusItem?.menu = menu
        rebuildMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    public func rebuildMenu() {
        menu.removeAllItems()

        // 1. Screen Topology Header
        let topo = ScreenManager.shared.getTopologySummary()
        let topoItem = NSMenuItem(title: "🖥️  \(topo)", action: nil, keyEquivalent: "")
        topoItem.isEnabled = false
        menu.addItem(topoItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Profiles Section
        let profiles = ProfileStore.shared.getProfiles()
        let profileNames = profiles.keys.sorted()

        // ⌘⌥⌃1…9 follow the order shown in the menu
        HotKeyManager.shared.registerProfileHotKeys(profileNames) { name in
            WindowManager.shared.applyProfile(named: name)
        }

        let wsHeader = NSMenuItem(title: "WORKSPACES", action: nil, keyEquivalent: "")
        wsHeader.isEnabled = false
        menu.addItem(wsHeader)

        if profileNames.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No profiles saved yet)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (position, name) in profileNames.enumerated() {
                guard let p = profiles[name] else { continue }
                let isLast = (WindowManager.shared.lastActiveProfileName == name)
                let prefix = isLast ? "✓ " : "▶ "
                let title = "  \(prefix)\(name)  (\(p.screenCount) scr)"
                let keyEquivalent = HotKeyManager.profileKeyEquivalent(at: position)

                // Hover opens the profile's contents; applying is the first submenu entry
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent ?? "")
                item.keyEquivalentModifierMask = [.command, .option, .control]
                item.submenu = buildProfileSubmenu(name: name, profile: p, keyEquivalent: keyEquivalent)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // 3. Actions Section
        let snapItem = NSMenuItem(title: "📸  Snapshot Current Layout...", action: #selector(handleSnapshot), keyEquivalent: "")
        snapItem.target = self
        menu.addItem(snapItem)

        // Shortcut shown for reference; it is handled globally by HotKeyManager
        let resnapItem = NSMenuItem(title: "🔄  Re-Snap Current Windows", action: #selector(handleResnap), keyEquivalent: "g")
        resnapItem.keyEquivalentModifierMask = [.command, .option, .control]
        resnapItem.target = self
        menu.addItem(resnapItem)

        let minimizeAllItem = NSMenuItem(title: "🔽  Minimize All Windows", action: #selector(handleMinimizeAll), keyEquivalent: "")
        minimizeAllItem.target = self
        menu.addItem(minimizeAllItem)

        // Delete Profile Submenu
        if !profileNames.isEmpty {
            let deleteSubmenu = NSMenu()
            for name in profileNames {
                let dItem = NSMenuItem(title: "Delete '\(name)'", action: #selector(handleDeleteProfile(_:)), keyEquivalent: "")
                dItem.target = self
                dItem.representedObject = name
                deleteSubmenu.addItem(dItem)
            }
            let deleteMenuItem = NSMenuItem(title: "🗑  Delete Profile", action: nil, keyEquivalent: "")
            deleteMenuItem.submenu = deleteSubmenu
            menu.addItem(deleteMenuItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Focus / Isolation Option
        let minItem = NSMenuItem(title: "Minimize Other Windows on Switch", action: #selector(handleToggleMinimizeOthers), keyEquivalent: "")
        minItem.state = WindowManager.shared.shouldMinimizeOthers ? .on : .off
        minItem.target = self
        menu.addItem(minItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        let revealItem = NSMenuItem(title: "Show Profiles File in Finder", action: #selector(handleRevealProfiles), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Quit
        let quitItem = NSMenuItem(title: "Quit GRID", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Submenu listing every window/file/site a profile restores, each removable with ✕
    private func buildProfileSubmenu(name: String, profile: WorkspaceProfile, keyEquivalent: String?) -> NSMenu {
        let sub = NSMenu()

        let apply = NSMenuItem(title: "▶  Apply Workspace", action: #selector(handleSelectProfile(_:)), keyEquivalent: keyEquivalent ?? "")
        apply.keyEquivalentModifierMask = [.command, .option, .control]
        sub.addItem(apply)

        let update = NSMenuItem(title: "🔄  Update from Current Layout…", action: #selector(handleUpdateProfile(_:)), keyEquivalent: "")
        sub.addItem(update)

        let rename = NSMenuItem(title: "✏️  Rename…", action: #selector(handleRenameProfile(_:)), keyEquivalent: "")
        sub.addItem(rename)

        let duplicate = NSMenuItem(title: "⧉  Duplicate…", action: #selector(handleDuplicateProfile(_:)), keyEquivalent: "")
        sub.addItem(duplicate)

        for item in [apply, update, rename, duplicate] {
            item.target = self
            item.representedObject = name
        }

        sub.addItem(NSMenuItem.separator())

        let header = NSMenuItem(title: windowsHeaderTitle(count: profile.windows.count), action: nil, keyEquivalent: "")
        header.isEnabled = false
        sub.addItem(header)

        if profile.windows.isEmpty {
            sub.addItem(emptyWindowsItem())
        }

        for win in profile.windows {
            let row = NSMenuItem()
            row.view = ProfileWindowRowView(window: win) { [weak self, weak sub, weak row] in
                guard let self = self, let sub = sub, let row = row else { return }
                self.removeWindow(win, fromProfile: name, row: row, in: sub, header: header)
            }
            sub.addItem(row)
        }

        return sub
    }

    private func windowsHeaderTitle(count: Int) -> String {
        return "WINDOWS (\(count))"
    }

    private func emptyWindowsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "  (No windows in this workspace)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Removes the window from the saved profile and updates the open submenu in place
    private func removeWindow(_ window: WindowSnapshot, fromProfile name: String, row: NSMenuItem, in sub: NSMenu, header: NSMenuItem) {
        guard let updated = ProfileStore.shared.removeWindow(window, fromProfile: name) else { return }
        sub.removeItem(row)
        header.title = windowsHeaderTitle(count: updated.windows.count)
        if updated.windows.isEmpty {
            sub.addItem(emptyWindowsItem())
        }
    }

    @objc private func handleToggleMinimizeOthers() {
        WindowManager.shared.shouldMinimizeOthers.toggle()
        rebuildMenu()
    }

    @objc private func handleToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.app.error("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Couldn't Change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also add GRID manually in System Settings ➔ General ➔ Login Items."
            alert.alertStyle = .warning
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func handleRevealProfiles() {
        let url = ProfileStore.shared.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    @objc private func handleSelectProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        WindowManager.shared.applyProfile(named: name)
    }

    @objc private func handleMinimizeAll() {
        WindowManager.shared.minimizeAllWindows()
    }

    @objc private func handleResnap() {
        WindowManager.shared.resnapCurrent()
    }

    @objc private func handleSnapshot() {
        guard let snapshots = captureOrExplain() else { return }

        let message = "Enter a name for this workspace profile (\(snapshots.count) windows captured across \(ScreenManager.shared.screenCount) display(s)):"
        guard let name = promptForName(
            title: "Save Workspace Snapshot",
            message: message,
            defaultValue: "Workspace (\(ScreenManager.shared.screenCount) screens)",
            confirmTitle: "Save Profile"
        ) else { return }

        if ProfileStore.shared.profileExists(named: name) && !confirmOverwrite(name: name) {
            return
        }

        ProfileStore.shared.saveProfile(named: name, profile: makeProfile(name: name, windows: snapshots))
        rebuildMenu()
    }

    @objc private func handleUpdateProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let snapshots = captureOrExplain() else { return }

        let alert = NSAlert()
        alert.messageText = "Update '\(name)'?"
        alert.informativeText = "Replace this workspace's saved layout with the \(snapshots.count) windows currently open across \(ScreenManager.shared.screenCount) display(s)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        ProfileStore.shared.saveProfile(named: name, profile: makeProfile(name: name, windows: snapshots))
        rebuildMenu()
    }

    @objc private func handleRenameProfile(_ sender: NSMenuItem) {
        guard let oldName = sender.representedObject as? String,
              let newName = promptForUniqueName(
                  title: "Rename '\(oldName)'",
                  message: "Enter a new name for this workspace:",
                  defaultValue: oldName,
                  confirmTitle: "Rename",
                  unchangedAllowed: oldName
              ),
              newName != oldName else { return }

        if ProfileStore.shared.renameProfile(from: oldName, to: newName) {
            WindowManager.shared.profileRenamed(from: oldName, to: newName)
        }
        rebuildMenu()
    }

    @objc private func handleDuplicateProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let newName = promptForUniqueName(
                  title: "Duplicate '\(name)'",
                  message: "Enter a name for the copy:",
                  defaultValue: "\(name) copy",
                  confirmTitle: "Duplicate",
                  unchangedAllowed: nil
              ) else { return }

        ProfileStore.shared.duplicateProfile(name, as: newName)
        rebuildMenu()
    }

    /// Captures visible windows, or explains why nothing could be captured and returns nil
    private func captureOrExplain() -> [WindowSnapshot]? {
        let snapshots = WindowManager.shared.captureVisibleWindows()
        if !snapshots.isEmpty {
            return snapshots
        }

        let isTrusted = WindowManager.shared.ensureAccessibilityPermissions()
        let alert = NSAlert()

        if !isTrusted {
            alert.messageText = "Accessibility Permissions Need Refresh"
            alert.informativeText = "GRID was recently updated on your Mac. Even if GRID is already toggled ON in System Settings, macOS requires you to toggle it OFF and back ON (or remove it with '-' and re-add it) to recognize the update.\n\nAfter refreshing the toggle, click Restart GRID."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Restart GRID")
            alert.addButton(withTitle: "Cancel")

            NSApplication.shared.activate(ignoringOtherApps: true)
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } else if resp == .alertSecondButtonReturn {
                restartApp()
            }
        } else {
            alert.messageText = "No Windows Detected"
            alert.informativeText = "No active standard application windows were found to snapshot. Please make sure applications are open and visible."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        return nil
    }

    private func makeProfile(name: String, windows: [WindowSnapshot]) -> WorkspaceProfile {
        let screensMeta = ScreenManager.shared.getSortedScreens().map {
            ScreenMeta(index: $0.index, name: $0.name, uuid: $0.uuid)
        }
        return WorkspaceProfile(
            name: name,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            screenCount: ScreenManager.shared.screenCount,
            screens: screensMeta,
            windows: windows
        )
    }

    /// Text-input alert; returns the trimmed, non-empty name or nil if cancelled
    private func promptForName(title: String, message: String, defaultValue: String, confirmTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input

        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Like promptForName, but re-asks while the name belongs to another profile
    private func promptForUniqueName(title: String, message: String, defaultValue: String, confirmTitle: String, unchangedAllowed: String?) -> String? {
        var current = defaultValue
        var prompt = message
        while true {
            guard let name = promptForName(title: title, message: prompt, defaultValue: current, confirmTitle: confirmTitle) else {
                return nil
            }
            if name == unchangedAllowed || !ProfileStore.shared.profileExists(named: name) {
                return name
            }
            current = name
            prompt = "A workspace named '\(name)' already exists. Choose a different name:"
        }
    }

    private func confirmOverwrite(name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Replace '\(name)'?"
        alert.informativeText = "A workspace profile with this name already exists. Replacing it will overwrite its saved layout."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func handleDeleteProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        ProfileStore.shared.deleteProfile(named: name)
        WindowManager.shared.forgetProfile(named: name)
        rebuildMenu()
    }

    private func restartApp() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
