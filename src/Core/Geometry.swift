import CoreGraphics
import Foundation

/// Pure coordinate math shared by the app and the tests
public enum Geometry {
    /// Converts a Cocoa frame (bottom-left origin) to Accessibility coordinates (top-left origin)
    public static func cocoaToAx(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let axY = primaryScreenHeight - (frame.origin.y + frame.size.height)
        return CGRect(x: frame.origin.x, y: axY, width: frame.size.width, height: frame.size.height)
    }

    /// Normalizes an AX window frame to fractions [0.0 - 1.0] of a screen's AX frame
    public static func normalize(_ axFrame: CGRect, in screen: CGRect) -> WindowRect {
        let rx = (axFrame.origin.x - screen.origin.x) / screen.width
        let ry = (axFrame.origin.y - screen.origin.y) / screen.height
        let rw = axFrame.width / screen.width
        let rh = axFrame.height / screen.height

        let clampedX = max(0.0, min(1.0, Double(rx)))
        let clampedY = max(0.0, min(1.0, Double(ry)))
        let clampedW = max(0.05, min(1.0, Double(rw)))
        let clampedH = max(0.05, min(1.0, Double(rh)))

        let round4 = { (v: Double) -> Double in
            return (v * 10000.0).rounded() / 10000.0
        }

        return WindowRect(x: round4(clampedX), y: round4(clampedY), w: round4(clampedW), h: round4(clampedH))
    }

    /// Denormalizes fractions [0.0 - 1.0] back to a screen's AX pixel frame
    public static func denormalize(_ rect: WindowRect, in screen: CGRect) -> CGRect {
        let x = screen.origin.x + (CGFloat(rect.x) * screen.width)
        let y = screen.origin.y + (CGFloat(rect.y) * screen.height)
        let w = CGFloat(rect.w) * screen.width
        let h = CGFloat(rect.h) * screen.height

        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }
}

/// Matching rules used when restoring windows
public enum Matching {
    /// Host without a leading "www.", lowercased
    public static func host(of urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Two URLs point at the same site (e.g. web.whatsapp.com/… with different paths or fragments)
    public static func sameSite(_ a: String, _ b: String) -> Bool {
        if let ha = host(of: a), let hb = host(of: b) {
            return ha == hb
        }
        return a == b
    }

    /// An AX window title corresponds to a scripting window/document title.
    /// Apps often append or drop suffixes (" - Google Chrome", ".xlsx"), so prefixes match too.
    public static func titlesMatch(_ axTitle: String, _ scriptTitle: String) -> Bool {
        if axTitle.isEmpty || scriptTitle.isEmpty { return false }
        return axTitle == scriptTitle || axTitle.hasPrefix(scriptTitle) || scriptTitle.hasPrefix(axTitle)
    }
}
