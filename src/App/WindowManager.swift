import AppKit
import ApplicationServices
import Foundation
import GRIDCore

public final class WindowManager {
    public static let shared = WindowManager()

    /// Max seconds to wait on an unresponsive app for any single AX call
    private static let axMessagingTimeout: Float = 1.0
    /// Launch polling: 30 × 0.5s = 15s, enough for cold launches of heavy apps (Excel, Xcode)
    private static let pollInterval: TimeInterval = 0.5
    private static let maxPollAttempts = 30

    private static let lastProfileKey = "lastActiveProfileName"
    private static let minimizeOthersKey = "minimizeOtherWindows"

    /// In-flight launch poller, cancelled when a new profile is applied
    private var pollTimer: Timer?

    private init() {}

    // MARK: - Settings

    public private(set) var lastActiveProfileName: String? {
        get { UserDefaults.standard.string(forKey: Self.lastProfileKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastProfileKey) }
    }

    /// Off by default — minimizing other apps' windows is opt-in
    public var shouldMinimizeOthers: Bool {
        get { UserDefaults.standard.bool(forKey: Self.minimizeOthersKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.minimizeOthersKey) }
    }

    /// Clears the "last active" marker when its profile is deleted
    public func forgetProfile(named name: String) {
        if lastActiveProfileName == name {
            lastActiveProfileName = nil
        }
    }

    /// Keeps the "last active" marker pointing at a renamed profile
    public func profileRenamed(from oldName: String, to newName: String) {
        if lastActiveProfileName == oldName {
            lastActiveProfileName = newName
        }
    }

    // MARK: - Permissions

    /// Verifies and prompts for macOS Accessibility permissions
    @discardableResult
    public func ensureAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - AX helpers

    private var managedApps: [NSRunningApplication] {
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    private func appElement(for app: NSRunningApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        return element
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref
    }

    private func isMinimized(_ win: AXUIElement) -> Bool {
        return (copyAttribute(win, kAXMinimizedAttribute) as? Bool) ?? false
    }

    private func title(of win: AXUIElement) -> String {
        return (copyAttribute(win, kAXTitleAttribute) as? String) ?? ""
    }

    private func frame(of win: AXUIElement) -> CGRect? {
        guard let posRef = copyAttribute(win, kAXPositionAttribute),
              let sizeRef = copyAttribute(win, kAXSizeAttribute),
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// File path exposed by the window itself (works for most document-based apps)
    private func axDocumentPath(of win: AXUIElement) -> String? {
        guard let docStr = copyAttribute(win, "AXDocument") as? String else { return nil }
        if let url = URL(string: docStr), url.isFileURL {
            return url.path
        }
        return FileManager.default.fileExists(atPath: docStr) ? docStr : nil
    }

    /// Standard AX windows of an app (role AXWindow, not tiny helper panels)
    private func getWindows(for app: NSRunningApplication, includeMinimized: Bool) -> [AXUIElement] {
        guard let windows = copyAttribute(appElement(for: app), kAXWindowsAttribute) as? [AXUIElement] else {
            return []
        }
        return windows.filter { win in
            if let role = copyAttribute(win, kAXRoleAttribute) as? String, role != (kAXWindowRole as String) {
                return false
            }
            if !includeMinimized && isMinimized(win) {
                return false
            }
            return true
        }
    }

    private func contains(_ used: [AXUIElement], _ win: AXUIElement) -> Bool {
        // A fresh AXUIElement is created on every query, so compare by identity of the
        // underlying window (CFEqual), never by pointer or description.
        return used.contains { CFEqual($0, win) }
    }

    // MARK: - Capture

    /// Captures all standard visible windows across all running regular applications
    public func captureVisibleWindows() -> [WindowSnapshot] {
        if !AXIsProcessTrusted() {
            Log.windows.notice("AXIsProcessTrusted reports false. Attempting capture anyway...")
        }

        var snapshots: [WindowSnapshot] = []

        for app in managedApps {
            let appName = app.localizedName ?? "Unknown"
            let bundleID = app.bundleIdentifier ?? ""
            let windows = getWindows(for: app, includeMinimized: false)
            if windows.isEmpty { continue }

            // One query per app, then paired to each window by title
            let urlEntries = ScriptBridge.isBrowser(bundleID) ? ScriptBridge.browserWindows(bundleID: bundleID) : []
            let docEntries = ScriptBridge.supportsDocuments(bundleID) ? ScriptBridge.documentWindows(bundleID: bundleID) : []

            for win in windows {
                // Filter out zero-size or invisible helper windows
                guard let axFrame = frame(of: win), axFrame.width > 50, axFrame.height > 50,
                      let screen = ScreenManager.shared.findScreen(forAxFrame: axFrame) else {
                    continue
                }

                let windowTitle = title(of: win)
                let targetUrl = ScriptBridge.entry(forWindowTitle: windowTitle, in: urlEntries)?.value
                let filePath = axDocumentPath(of: win)
                    ?? ScriptBridge.entry(forWindowTitle: windowTitle, in: docEntries)?.value

                snapshots.append(WindowSnapshot(
                    appName: appName,
                    bundleID: bundleID,
                    windowTitle: windowTitle,
                    screenIndex: screen.index,
                    screenName: screen.name,
                    screenUUID: screen.uuid,
                    rect: ScreenManager.shared.normalize(axFrame: axFrame, on: screen),
                    targetUrl: targetUrl,
                    filePath: filePath
                ))
            }
        }

        return snapshots
    }

    // MARK: - Isolation

    /// Minimizes all windows belonging to applications outside of the target profile
    public func minimizeWindowsOutside(profile: WorkspaceProfile) {
        let profileBundleIDs = Set(profile.windows.compactMap { $0.bundleID.isEmpty ? nil : $0.bundleID })
        let profileAppNames = Set(profile.windows.map { $0.appName })

        for app in managedApps {
            let isProfileApp = (app.bundleIdentifier.map { profileBundleIDs.contains($0) } ?? false)
                || profileAppNames.contains(app.localizedName ?? "")
            if isProfileApp { continue }

            for win in getWindows(for: app, includeMinimized: false) {
                // Native macOS Genie Effect into Dock
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    /// Minimizes every standard window of every regular app to the Dock
    public func minimizeAllWindows() {
        for app in managedApps {
            for win in getWindows(for: app, includeMinimized: false) {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }
    }

    // MARK: - Restore

    /// A live window with the URL / document it currently shows
    private struct LiveWindow {
        let element: AXUIElement
        let title: String
        let url: String?
        let filePath: String?
    }

    private func liveWindows(for app: NSRunningApplication) -> [LiveWindow] {
        let bundleID = app.bundleIdentifier ?? ""
        let windows = getWindows(for: app, includeMinimized: true)
        if windows.isEmpty { return [] }

        let urlEntries = ScriptBridge.isBrowser(bundleID) ? ScriptBridge.browserWindows(bundleID: bundleID) : []
        let docEntries = ScriptBridge.supportsDocuments(bundleID) ? ScriptBridge.documentWindows(bundleID: bundleID) : []

        return windows.map { win in
            let t = title(of: win)
            return LiveWindow(
                element: win,
                title: t,
                url: ScriptBridge.entry(forWindowTitle: t, in: urlEntries)?.value,
                filePath: axDocumentPath(of: win) ?? ScriptBridge.entry(forWindowTitle: t, in: docEntries)?.value
            )
        }
    }

    private func runningApp(for def: WindowSnapshot) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if !def.bundleID.isEmpty, let app = apps.first(where: { $0.bundleIdentifier == def.bundleID }) {
            return app
        }
        return apps.first { $0.localizedName == def.appName }
    }

    /// Exact match: same document, same site, or (for plain windows) same title
    private func strictMatch(_ def: WindowSnapshot, in windows: [LiveWindow], used: [AXUIElement]) -> AXUIElement? {
        let free = windows.filter { !contains(used, $0.element) }
        if let path = def.filePath, !path.isEmpty {
            return free.first { $0.filePath == path }?.element
        }
        if let url = def.targetUrl, !url.isEmpty {
            return free.first { live in live.url.map { Matching.sameSite($0, url) } ?? false }?.element
        }
        if !def.windowTitle.isEmpty {
            return free.first { $0.title == def.windowTitle }?.element
        }
        return nil
    }

    /// Fallback for plain windows only: any window of the app not claimed yet
    private func looseMatch(_ def: WindowSnapshot, in windows: [LiveWindow], used: [AXUIElement]) -> AXUIElement? {
        guard !def.hasTarget else { return nil }
        return windows.first { !contains(used, $0.element) }?.element
    }

    private func snap(_ element: AXUIElement, to def: WindowSnapshot) {
        guard let screen = ScreenManager.shared.findTargetScreen(
            savedIndex: def.screenIndex, savedName: def.screenName, savedUUID: def.screenUUID
        ) else { return }
        snap(element: element, to: ScreenManager.shared.denormalize(rect: def.rect, on: screen))
    }

    /// Snaps a specific AX window element to target frame
    private func snap(element: AXUIElement, to targetFrame: CGRect) {
        // Un-minimize if it was minimized
        if isMinimized(element) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var origin = targetFrame.origin
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }

        var size = targetFrame.size
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }

        // Second pass position to ensure proper anchoring
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }
    }

    /// Snaps every window it can match and returns the definitions still unmatched.
    /// Exact matches run first for all windows so a plain fallback never steals a window
    /// that another definition matches exactly.
    private func snapPass(_ defs: [WindowSnapshot], used: inout [AXUIElement]) -> [WindowSnapshot] {
        var cache: [pid_t: [LiveWindow]] = [:]
        func windows(for app: NSRunningApplication) -> [LiveWindow] {
            if let cached = cache[app.processIdentifier] { return cached }
            let live = liveWindows(for: app)
            cache[app.processIdentifier] = live
            return live
        }

        var needsFallback: [WindowSnapshot] = []
        for def in defs {
            if let app = runningApp(for: def), let win = strictMatch(def, in: windows(for: app), used: used) {
                used.append(win)
                snap(win, to: def)
            } else {
                needsFallback.append(def)
            }
        }

        var unresolved: [WindowSnapshot] = []
        for def in needsFallback {
            if let app = runningApp(for: def), let win = looseMatch(def, in: windows(for: app), used: used) {
                used.append(win)
                snap(win, to: def)
            } else {
                unresolved.append(def)
            }
        }
        return unresolved
    }

    /// Restores a full workspace profile
    public func applyProfile(named name: String, completion: ((Bool) -> Void)? = nil) {
        guard let profile = ProfileStore.shared.getProfile(named: name) else {
            Log.windows.error("Profile '\(name, privacy: .public)' not found.")
            completion?(false)
            return
        }

        pollTimer?.invalidate()
        pollTimer = nil
        lastActiveProfileName = name

        // Minimize non-profile windows if enabled
        if shouldMinimizeOthers {
            minimizeWindowsOutside(profile: profile)
        }

        var used: [AXUIElement] = []
        var pending = snapPass(profile.windows, used: &used)

        if pending.isEmpty {
            completion?(true)
            return
        }

        // Open what is missing: URLs and documents individually, plain apps once each
        var launchedPlain = Set<String>()
        for def in pending {
            if !def.hasTarget {
                let key = def.bundleID.isEmpty ? def.appName : def.bundleID
                if !launchedPlain.insert(key).inserted { continue }
            }
            launchApp(snapshot: def)
        }

        // Poll until launched apps/windows appear
        var attempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1
            pending = self.snapPass(pending, used: &used)

            if pending.isEmpty || attempts >= Self.maxPollAttempts {
                timer.invalidate()
                self.pollTimer = nil
                if !pending.isEmpty {
                    let names = pending.map { "\($0.appName) '\($0.windowTitle)'" }.joined(separator: ", ")
                    Log.windows.notice("Gave up waiting for: \(names, privacy: .private)")
                }
                completion?(pending.isEmpty)
            }
        }
    }

    private func applicationURL(for snapshot: WindowSnapshot) -> URL? {
        if !snapshot.bundleID.isEmpty {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: snapshot.bundleID)
        }
        return nil
    }

    private func launchApp(snapshot: WindowSnapshot) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        // Priority 1: Specific URL — in a new window of a running browser so no saved window loses its tab
        // Only web URLs are opened, so a hand-edited or shared profile can't trigger other URL schemes
        if let targetUrl = snapshot.targetUrl, !targetUrl.isEmpty, let url = URL(string: targetUrl),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            if runningApp(for: snapshot) != nil, ScriptBridge.openInNewWindow(bundleID: snapshot.bundleID, url: targetUrl) {
                return
            }
            if let appUrl = applicationURL(for: snapshot) {
                NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: config, completionHandler: nil)
            } else {
                openWithLaunchServices(appName: snapshot.appName, argument: targetUrl)
            }
            return
        }

        // Priority 2: Specific Document File (e.g. Numbers / Excel spreadsheet)
        if let path = snapshot.filePath, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            if let appUrl = applicationURL(for: snapshot) {
                NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appUrl, configuration: config, completionHandler: nil)
            } else {
                openWithLaunchServices(appName: snapshot.appName, argument: path)
            }
            return
        }

        // Priority 3: Standard app launch by Bundle ID or localized name
        if let appUrl = applicationURL(for: snapshot) {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: config, completionHandler: nil)
        } else {
            openWithLaunchServices(appName: snapshot.appName, argument: nil)
        }
    }

    private func openWithLaunchServices(appName: String, argument: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName] + (argument.map { [$0] } ?? [])
        do {
            try process.run()
        } catch {
            Log.windows.error("Failed to open \(appName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-snaps the current workspace windows
    public func resnapCurrent() {
        if let last = lastActiveProfileName, ProfileStore.shared.profileExists(named: last) {
            applyProfile(named: last)
        } else if let firstProfileName = ProfileStore.shared.getProfiles().keys.sorted().first {
            applyProfile(named: firstProfileName)
        }
    }
}
