import Foundation
import GRIDCore

public final class ProfileStore {
    public static let shared = ProfileStore()

    /// ~/Library/Application Support/GRID/profiles.json
    public let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GRID")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("profiles.json")
    }

    public func loadContainer() -> ProfileStoreContainer {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return ProfileStoreContainer(profiles: [:])
        }

        do {
            return try JSONDecoder().decode(ProfileStoreContainer.self, from: data)
        } catch {
            Log.store.error("Error decoding profiles.json: \(error.localizedDescription, privacy: .public)")
            return ProfileStoreContainer(profiles: [:])
        }
    }

    public func saveContainer(_ container: ProfileStoreContainer) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(container)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.store.error("Error writing profiles.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func getProfiles() -> [String: WorkspaceProfile] {
        return loadContainer().profiles
    }

    public func getProfile(named name: String) -> WorkspaceProfile? {
        return loadContainer().profiles[name]
    }

    public func profileExists(named name: String) -> Bool {
        return loadContainer().profiles[name] != nil
    }

    public func saveProfile(named name: String, profile: WorkspaceProfile) {
        var container = loadContainer()
        container.profiles[name] = profile
        saveContainer(container)
    }

    /// Removes one saved window from a profile. Returns the updated profile.
    @discardableResult
    public func removeWindow(_ window: WindowSnapshot, fromProfile name: String) -> WorkspaceProfile? {
        var container = loadContainer()
        guard var profile = container.profiles[name],
              let idx = profile.windows.firstIndex(of: window) else {
            return nil
        }
        profile.windows.remove(at: idx)
        container.profiles[name] = profile
        saveContainer(container)
        return profile
    }

    /// Renames a profile, keeping its layout. Fails if the new name is taken.
    @discardableResult
    public func renameProfile(from oldName: String, to newName: String) -> Bool {
        var container = loadContainer()
        guard oldName != newName,
              container.profiles[newName] == nil,
              var profile = container.profiles.removeValue(forKey: oldName) else {
            return false
        }
        profile.name = newName
        container.profiles[newName] = profile
        saveContainer(container)
        return true
    }

    /// Copies a profile under a new name. Fails if the new name is taken.
    @discardableResult
    public func duplicateProfile(_ name: String, as newName: String) -> Bool {
        var container = loadContainer()
        guard container.profiles[newName] == nil, var copy = container.profiles[name] else {
            return false
        }
        copy.name = newName
        copy.createdAt = ISO8601DateFormatter().string(from: Date())
        container.profiles[newName] = copy
        saveContainer(container)
        return true
    }

    public func deleteProfile(named name: String) {
        var container = loadContainer()
        container.profiles.removeValue(forKey: name)
        saveContainer(container)
    }
}
