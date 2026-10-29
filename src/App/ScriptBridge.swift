import Foundation
import GRIDCore

/// AppleScript queries for per-window browser URLs and document paths.
/// Every query lists *all* windows of the app, so each AX window can be paired
/// with its own URL/file instead of whatever happens to be frontmost.
enum ScriptBridge {
    struct Entry {
        let title: String
        let value: String
    }

    /// Chromium-family browsers sharing Chrome's scripting dictionary
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", // Arc
    ]

    private static let safariBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    private static let numbersBundleID = "com.apple.iWork.Numbers"
    private static let excelBundleID = "com.microsoft.Excel"

    static func isBrowser(_ bundleID: String) -> Bool {
        return chromiumBundleIDs.contains(bundleID) || safariBundleIDs.contains(bundleID)
    }

    static func supportsDocuments(_ bundleID: String) -> Bool {
        return bundleID == numbersBundleID || bundleID == excelBundleID
    }

    /// (window title, active tab URL) for every window of a running browser
    static func browserWindows(bundleID: String) -> [Entry] {
        let body: String
        if chromiumBundleIDs.contains(bundleID) {
            body = """
            repeat with w in windows
                try
                    set u to URL of active tab of w
                    set t to ""
                    try
                        set t to title of w
                    end try
                    set out to out & t & tab & u & linefeed
                end try
            end repeat
            """
        } else if safariBundleIDs.contains(bundleID) {
            body = """
            repeat with w in windows
                try
                    set out to out & (name of w) & tab & (URL of current tab of w) & linefeed
                end try
            end repeat
            """
        } else {
            return []
        }
        return run(bundleID: bundleID, body: body).filter { $0.value.hasPrefix("http") }
    }

    /// (document name, POSIX path) for every open document of Numbers / Excel
    static func documentWindows(bundleID: String) -> [Entry] {
        let body: String
        if bundleID == numbersBundleID {
            body = """
            repeat with d in documents
                try
                    set out to out & (name of d) & tab & (POSIX path of (file of d as alias)) & linefeed
                end try
            end repeat
            """
        } else if bundleID == excelBundleID {
            body = """
            repeat with w in workbooks
                try
                    set out to out & (name of w) & tab & (POSIX path of (full name of w)) & linefeed
                end try
            end repeat
            """
        } else {
            return []
        }
        return run(bundleID: bundleID, body: body).filter { FileManager.default.fileExists(atPath: $0.value) }
    }

    /// Opens a URL in a brand-new window of a running browser. Returns false if unsupported or failed.
    static func openInNewWindow(bundleID: String, url: String) -> Bool {
        let escaped = url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let body: String
        if chromiumBundleIDs.contains(bundleID) {
            body = """
            set w to make new window
            set URL of active tab of w to "\(escaped)"
            """
        } else if safariBundleIDs.contains(bundleID) {
            body = "make new document with properties {URL:\"\(escaped)\"}"
        } else {
            return false
        }
        var error: NSDictionary?
        let source = "tell application id \"\(bundleID)\"\n\(body)\nend tell"
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            Log.windows.notice("Opening new window in \(bundleID, privacy: .public) failed: \(error, privacy: .public)")
            return false
        }
        return true
    }

    /// Picks the entry for one AX window: by title, or the only entry when there is just one
    static func entry(forWindowTitle title: String, in entries: [Entry]) -> Entry? {
        if let match = entries.first(where: { Matching.titlesMatch(title, $0.title) }) {
            return match
        }
        return entries.count == 1 ? entries[0] : nil
    }

    private static func run(bundleID: String, body: String) -> [Entry] {
        let source = """
        tell application id "\(bundleID)"
            set out to ""
            \(body)
            return out
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let output = script.executeAndReturnError(&error)
        if let error = error {
            Log.windows.notice("AppleScript query to \(bundleID, privacy: .public) failed: \(error, privacy: .public)")
            return []
        }
        return (output.stringValue ?? "")
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                return Entry(title: String(parts[0]), value: String(parts[1]))
            }
    }
}
