import Carbon.HIToolbox

/// Carbon hotkeys, unlike NSEvent monitors, need no Accessibility permission. It lives as long as the
/// app, so it never unregisters.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x4146_5452), id: 1)  // 'AFTR'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    static func toggle(_ action: @escaping () -> Void) -> HotKey {
        HotKey(keyCode: kVK_ANSI_L, modifiers: cmdKey | optionKey, action: action)
    }
}
