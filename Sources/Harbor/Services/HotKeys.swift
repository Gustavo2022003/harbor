import AppKit
import Carbon.HIToolbox

/// Atalhos globais via Carbon (não precisam de permissão de Acessibilidade).
final class HotKeys {
    struct Combo {
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
    }

    static let toggle = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "⌥ Espaço")
    static let clipboard = Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey), label: "⌥ V")
    static let note = Combo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey), label: "⌥ N")
    static let pinApp = Combo(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(optionKey), label: "⌥ P")
    static let picker = Combo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | shiftKey), label: "⌥ ⇧ C")

    private var refs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let me = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.handlers[hk.id]?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ combo: Combo, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4842_5252), id: id) // "HBRR"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        refs.append(ref)
        handlers[id] = action
    }
}
