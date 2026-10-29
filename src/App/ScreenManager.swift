import AppKit
import Foundation
import GRIDCore

public final class ScreenManager {
    public static let shared = ScreenManager()

    private init() {}

    public struct ScreenInfo {
        public let index: Int // 1-based index
        public let name: String
        public let uuid: String?
        public let cocoaFrame: CGRect
        public let axFrame: CGRect // In Accessibility coordinates (top-left 0,0)
    }

    /// Primary screen height for Cocoa -> AX coordinate transformation
    private var primaryScreenHeight: CGFloat {
        return NSScreen.screens.first?.frame.height ?? 1080.0
    }

    /// Stable hardware UUID for a screen (survives reconnects and reordering)
    private func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Returns all connected screens sorted horizontally (left to right)
    public func getSortedScreens() -> [ScreenInfo] {
        let screens = NSScreen.screens
        let sorted = screens.sorted { a, b in
            if a.frame.origin.x == b.frame.origin.x {
                return a.frame.origin.y > b.frame.origin.y
            }
            return a.frame.origin.x < b.frame.origin.x
        }

        let pHeight = primaryScreenHeight
        return sorted.enumerated().map { idx, screen in
            let cFrame = screen.frame
            return ScreenInfo(
                index: idx + 1,
                name: screen.localizedName,
                uuid: displayUUID(for: screen),
                cocoaFrame: cFrame,
                axFrame: Geometry.cocoaToAx(cFrame, primaryScreenHeight: pHeight)
            )
        }
    }

    public var screenCount: Int {
        return NSScreen.screens.count
    }

    /// Finds the screen matching a window's center or frame in AX coordinates
    public func findScreen(forAxFrame frame: CGRect) -> ScreenInfo? {
        let screens = getSortedScreens()
        let center = CGPoint(x: frame.midX, y: frame.midY)

        if let screen = screens.first(where: { $0.axFrame.contains(center) }) {
            return screen
        }
        // Fallback: screen with maximum intersection
        var bestScreen: ScreenInfo?
        var maxArea: CGFloat = 0.0
        for screen in screens {
            let intersect = screen.axFrame.intersection(frame)
            if !intersect.isNull {
                let area = intersect.width * intersect.height
                if area > maxArea {
                    maxArea = area
                    bestScreen = screen
                }
            }
        }
        return bestScreen ?? screens.first
    }

    /// Finds target screen by saved UUID, then by (unique) name, then by index
    public func findTargetScreen(savedIndex: Int, savedName: String, savedUUID: String?) -> ScreenInfo? {
        let screens = getSortedScreens()
        if let uuid = savedUUID, !uuid.isEmpty,
           let match = screens.first(where: { $0.uuid == uuid }) {
            return match
        }
        if !savedName.isEmpty {
            // Identical monitor models share a name — only trust it when unambiguous
            let named = screens.filter { $0.name == savedName }
            if named.count == 1 {
                return named[0]
            }
        }
        if savedIndex >= 1 && savedIndex <= screens.count {
            return screens[savedIndex - 1]
        }
        return screens.first
    }

    public func normalize(axFrame: CGRect, on screen: ScreenInfo) -> WindowRect {
        return Geometry.normalize(axFrame, in: screen.axFrame)
    }

    public func denormalize(rect: WindowRect, on screen: ScreenInfo) -> CGRect {
        return Geometry.denormalize(rect, in: screen.axFrame)
    }

    public func getTopologySummary() -> String {
        let count = screenCount
        if count == 1 {
            return "1 Screen (Laptop Mode)"
        } else if count == 2 {
            return "2 Screens Connected"
        } else if count >= 3 {
            return "\(count) Screens (Office Mode)"
        }
        return "No Screens Detected"
    }
}
