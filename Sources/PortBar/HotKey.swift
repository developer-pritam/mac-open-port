import Carbon.HIToolbox

/// System-wide hotkey via Carbon's RegisterEventHotKey — works without Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlerInstalled = false
    /// Carbon calls back through a C function pointer, so the action lives in a static.
    static var onPress: (() -> Void)?

    /// Returns false if the combination is already taken by another app.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        guard shortcut != .off else { return true }
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { HotKey.onPress?() } }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5042_4152), id: 1) // 'PBAR'
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
