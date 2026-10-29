import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys (work while any app is focused, unlike NSMenuItem key equivalents)
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// All GRID hotkeys use ⌘⌥⌃
    static let modifiers = UInt32(cmdKey | optionKey | controlKey)
    /// ⌘⌥⌃1 … ⌘⌥⌃9 apply the first nine profiles (alphabetical order)
    static let profileSlotCount = 9
    private static let profileKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    private static let signature = OSType(0x4752_4944) // 'GRID'
    private static let resnapID: UInt32 = 1
    private static let profileBaseID: UInt32 = 100

    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var handlerRef: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    /// Profile names currently bound, to skip needless re-registration
    private var boundProfiles: [String] = []

    private init() {}

    /// Registers ⌘⌥⌃G
    func registerResnapHotKey(action: @escaping () -> Void) {
        register(id: Self.resnapID, keyCode: UInt32(kVK_ANSI_G), action: action)
    }

    /// Binds ⌘⌥⌃1…9 to the given profile names, in order
    func registerProfileHotKeys(_ names: [String], action: @escaping (String) -> Void) {
        let slotted = Array(names.prefix(Self.profileSlotCount))
        if slotted == boundProfiles { return }
        boundProfiles = slotted

        for slot in 0..<Self.profileSlotCount {
            unregister(id: Self.profileBaseID + UInt32(slot))
        }
        for (slot, name) in slotted.enumerated() {
            register(id: Self.profileBaseID + UInt32(slot), keyCode: UInt32(Self.profileKeyCodes[slot])) {
                action(name)
            }
        }
    }

    /// Menu key equivalent ("1"…"9") for a profile at this sorted position, if it has one
    static func profileKeyEquivalent(at position: Int) -> String? {
        return position < profileSlotCount ? String(position + 1) : nil
    }

    func unregisterAll() {
        for id in Array(registrations.keys) {
            unregister(id: id)
        }
        boundProfiles = []
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = manager.registrations[hotKeyID.id]?.action {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }

    private func register(id: UInt32, keyCode: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, Self.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            registrations[id] = Registration(ref: ref, action: action)
        } else {
            // Usually means another app already owns this shortcut
            Log.app.error("Failed to register hotkey \(id, privacy: .public) (status \(status, privacy: .public))")
        }
    }

    private func unregister(id: UInt32) {
        if let registration = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(registration.ref)
        }
    }
}
