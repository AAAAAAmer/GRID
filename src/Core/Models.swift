import Foundation

public struct WindowRect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct ScreenMeta: Codable, Equatable {
    public var index: Int
    public var name: String
    /// Stable hardware display UUID (distinguishes identical monitor models)
    public var uuid: String?

    public init(index: Int, name: String, uuid: String? = nil) {
        self.index = index
        self.name = name
        self.uuid = uuid
    }
}

public struct WindowSnapshot: Codable, Equatable {
    public var appName: String
    public var bundleID: String
    public var windowTitle: String
    public var screenIndex: Int
    public var screenName: String
    public var screenUUID: String?
    public var rect: WindowRect
    public var targetUrl: String?
    public var filePath: String?

    public init(
        appName: String,
        bundleID: String,
        windowTitle: String,
        screenIndex: Int,
        screenName: String,
        screenUUID: String? = nil,
        rect: WindowRect,
        targetUrl: String? = nil,
        filePath: String? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.screenIndex = screenIndex
        self.screenName = screenName
        self.screenUUID = screenUUID
        self.rect = rect
        self.targetUrl = targetUrl
        self.filePath = filePath
    }

    /// True when this window is tied to a specific URL or document
    public var hasTarget: Bool {
        return !(targetUrl ?? "").isEmpty || !(filePath ?? "").isEmpty
    }
}

public struct WorkspaceProfile: Codable, Equatable {
    public var name: String?
    public var createdAt: String?
    public var screenCount: Int
    public var screens: [ScreenMeta]?
    public var windows: [WindowSnapshot]

    public init(name: String? = nil, createdAt: String? = nil, screenCount: Int, screens: [ScreenMeta]? = nil, windows: [WindowSnapshot]) {
        self.name = name
        self.createdAt = createdAt
        self.screenCount = screenCount
        self.screens = screens
        self.windows = windows
    }
}

public struct ProfileStoreContainer: Codable {
    public var profiles: [String: WorkspaceProfile]

    public init(profiles: [String: WorkspaceProfile] = [:]) {
        self.profiles = profiles
    }
}
