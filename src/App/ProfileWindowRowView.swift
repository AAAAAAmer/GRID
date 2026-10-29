import AppKit
import GRIDCore

/// One saved window inside a profile's submenu: app icon, what it opens, screen, and an ✕ to remove it
final class ProfileWindowRowView: NSView {
    static let width: CGFloat = 340
    private static let height: CGFloat = 40

    private let onRemove: () -> Void

    init(window: WindowSnapshot, onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 24, height: 24))
        icon.image = Self.appIcon(for: window)
        addSubview(icon)

        let textWidth = Self.width - 46 - 36
        let title = NSTextField(labelWithString: Self.primaryText(for: window))
        title.frame = NSRect(x: 46, y: 20, width: textWidth, height: 16)
        title.font = .menuFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingMiddle
        addSubview(title)

        let detail = NSTextField(labelWithString: Self.detailText(for: window))
        detail.frame = NSRect(x: 46, y: 4, width: textWidth, height: 14)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        addSubview(detail)

        let remove = NSButton(frame: NSRect(x: Self.width - 32, y: 10, width: 20, height: 20))
        remove.bezelStyle = .regularSquare
        remove.isBordered = false
        remove.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove from workspace")
        remove.contentTintColor = .tertiaryLabelColor
        remove.toolTip = "Remove this window from the workspace"
        remove.target = self
        remove.action = #selector(removeClicked)
        addSubview(remove)

        toolTip = window.filePath ?? window.targetUrl ?? window.windowTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func removeClicked() {
        onRemove()
    }

    private static func appIcon(for window: WindowSnapshot) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
    }

    /// The document / site / window this entry restores
    private static func primaryText(for window: WindowSnapshot) -> String {
        if let path = window.filePath, !path.isEmpty {
            return "📄 " + (path as NSString).lastPathComponent
        }
        if let url = window.targetUrl, !url.isEmpty {
            return "🔗 " + (Matching.host(of: url) ?? url)
        }
        return window.windowTitle.isEmpty ? window.appName : window.windowTitle
    }

    private static func detailText(for window: WindowSnapshot) -> String {
        let screen = window.screenName.isEmpty ? "Screen \(window.screenIndex)" : window.screenName
        return "\(window.appName) · \(screen)"
    }
}
