import Carbon.HIToolbox

/// System-wide hotkey via Carbon `RegisterEventHotKey`.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, this consumes the keystroke (⌥Space won't also
/// type a non-breaking space into the frontmost app) and needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private static var nextID: UInt32 = 1
    private static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier mask (`optionKey`, `cmdKey`, …).
    init?(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x5641_4754), id: id) // 'VAGT'
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr else { return nil }
        Self.handlers[id] = action
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { GlobalHotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
