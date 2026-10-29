import CoreGraphics
import Foundation
import Testing
@testable import GRIDCore

@Suite struct GeometryTests {
    @Test func cocoaToAxOnPrimaryScreen() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        #expect(Geometry.cocoaToAx(frame, primaryScreenHeight: 1117) == frame)
    }

    @Test func cocoaToAxOnScreenAbovePrimary() {
        // External monitor placed above a 1117pt-tall laptop screen
        let frame = CGRect(x: -200, y: 1117, width: 2560, height: 1440)
        let ax = Geometry.cocoaToAx(frame, primaryScreenHeight: 1117)
        #expect(ax == CGRect(x: -200, y: -1440, width: 2560, height: 1440))
    }

    @Test func normalizeDenormalizeRoundTrip() {
        let screen = CGRect(x: 1728, y: -300, width: 2560, height: 1440)
        let window = CGRect(x: 1728 + 640, y: -300 + 360, width: 1280, height: 720)
        let norm = Geometry.normalize(window, in: screen)
        #expect(norm == WindowRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
        #expect(Geometry.denormalize(norm, in: screen) == window)
    }

    @Test func normalizeClampsOffscreenWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let norm = Geometry.normalize(CGRect(x: -100, y: 50, width: 2000, height: 10), in: screen)
        #expect(norm.x == 0)
        #expect(norm.w == 1)
        #expect(norm.h == 0.05)
    }

    @Test func normalizeAcrossDifferentScreenSizes() {
        let small = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let large = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let norm = Geometry.normalize(CGRect(x: 500, y: 0, width: 500, height: 500), in: small)
        #expect(Geometry.denormalize(norm, in: large) == CGRect(x: 2000, y: 0, width: 1000, height: 1000))
    }
}

@Suite struct MatchingTests {
    @Test func sameSiteIgnoresPathAndWww() {
        #expect(Matching.sameSite("https://web.whatsapp.com/", "https://web.whatsapp.com/#chat/123"))
        #expect(Matching.sameSite("https://www.github.com/a", "https://github.com/b"))
        #expect(!Matching.sameSite("https://web.whatsapp.com/", "https://mail.google.com/"))
    }

    @Test func titlesMatchWithSuffixes() {
        #expect(Matching.titlesMatch("WhatsApp - Brave", "WhatsApp"))
        #expect(Matching.titlesMatch("Budget", "Budget.xlsx"))
        #expect(!Matching.titlesMatch("", "Budget"))
        #expect(!Matching.titlesMatch("Inbox", "Budget"))
    }

    @Test func oldProfilesDecodeWithoutNewFields() throws {
        let json = """
        {"profiles":{"P":{"screenCount":1,"screens":[{"index":1,"name":"Built-in"}],
        "windows":[{"appName":"Finder","bundleID":"com.apple.finder","windowTitle":"x",
        "screenIndex":1,"screenName":"Built-in","rect":{"x":0,"y":0,"w":0.5,"h":0.5}}]}}}
        """
        let container = try JSONDecoder().decode(ProfileStoreContainer.self, from: Data(json.utf8))
        let win = try #require(container.profiles["P"]?.windows.first)
        #expect(win.screenUUID == nil)
        #expect(!win.hasTarget)
    }
}
