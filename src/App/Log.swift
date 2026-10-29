import os

/// Unified logging — view with Console.app (filter: subsystem com.amer.grid)
enum Log {
    private static let subsystem = "com.amer.grid"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let windows = Logger(subsystem: subsystem, category: "windows")
    static let store = Logger(subsystem: subsystem, category: "store")
}
