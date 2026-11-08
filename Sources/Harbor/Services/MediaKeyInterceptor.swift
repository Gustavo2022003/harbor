import AppKit
import ApplicationServices
import CoreAudio

/// Intercepta as teclas de volume/brilho (eventos NX_SYSDEFINED) antes do macOS,
/// aplica a mudança e "engole" o evento — assim o aviso nativo não aparece, só o do Harbor.
/// Requer permissão de Acessibilidade. Ao fechar o Harbor, o comportamento nativo volta.
final class MediaKeyInterceptor: ObservableObject {
    static let enabledKey = "replaceSystemHUD"

    @Published private(set) var active = false
    @Published private(set) var trusted = AXIsProcessTrusted()

    /// Chamado após mudar o brilho (para o aviso aparecer sem esperar o polling).
    var onBrightnessChange: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var loggedUntrusted = false

    // Códigos NX_KEYTYPE_*
    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    func start() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        refresh()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
    }

    /// Liga/desliga conforme a preferência e a permissão.
    func refresh() {
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        let want = UserDefaults.standard.bool(forKey: Self.enabledKey) && t
        if want && tap == nil {
            install()
            NSLog("Harbor keys: trusted=\(t) tapInstalled=\(tap != nil)")
        } else if !t && !loggedUntrusted {
            loggedUntrusted = true
            NSLog("Harbor keys: sem permissão de Acessibilidade (AXIsProcessTrusted=false)")
        }
        if !want && tap != nil { uninstall() }
        if active != (tap != nil) { active = tap != nil }
    }

    private func install() {
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                    .handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }

        let data1 = ns.data1
        guard let key = Key(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return pass }
        let keyFlags = data1 & 0x0000_FFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let fine = ns.modifierFlags.contains(.shift) && ns.modifierFlags.contains(.option)

        switch key {
        case .soundUp, .soundDown:
            guard SystemVolume.isAvailable else { return pass }
            if isDown { SystemVolume.step(up: key == .soundUp, fine: fine) }
            return nil
        case .mute:
            guard SystemVolume.isAvailable else { return pass }
            if isDown { SystemVolume.toggleMute() }
            return nil
        case .brightnessUp, .brightnessDown:
            guard DisplayBrightness.isAvailable else { return pass }
            if isDown {
                DisplayBrightness.step(up: key == .brightnessUp, fine: fine)
                onBrightnessChange?()
            }
            return nil
        }
    }
}

// MARK: - Volume (CoreAudio)

enum SystemVolume {
    private static var device: AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Elementos que controlam o volume (o "main" ou os canais 1 e 2).
    private static func volumeElements(_ dev: AudioObjectID) -> [AudioObjectPropertyElement] {
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &main),
           AudioObjectIsPropertySettable(dev, &main, &settable) == noErr, settable.boolValue {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { ch in
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: ch)
            return AudioObjectHasProperty(dev, &a)
        }
    }

    static var isAvailable: Bool { !volumeElements(device).isEmpty }

    static func get() -> Float {
        let dev = device
        let els = volumeElements(dev)
        guard !els.isEmpty else { return 0 }
        var total: Float = 0
        for el in els {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v)
            total += v
        }
        return total / Float(els.count)
    }

    static func set(_ value: Float) {
        let dev = device
        var v = Float32(min(1, max(0, value)))
        for el in volumeElements(dev) {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: el)
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    static var isMuted: Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let dev = device
        guard AudioObjectHasProperty(dev, &a),
              AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return false }
        return v != 0
    }

    static func setMuted(_ muted: Bool) {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = muted ? 1 : 0
        let dev = device
        guard AudioObjectHasProperty(dev, &a) else { return }
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }

    static func toggleMute() { setMuted(!isMuted) }

    /// Passo igual ao do macOS: 1/16 (ou 1/64 com ⌥⇧), alinhado à grade.
    static func step(up: Bool, fine: Bool) {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        if up && isMuted { setMuted(false) }
        let snapped = (get() / step).rounded() * step
        let next = min(1, max(0, snapped + (up ? step : -step)))
        set(next)
        if next <= 0.001 { setMuted(true) } else if isMuted && up { setMuted(false) }
    }
}

// MARK: - Brilho (DisplayServices — framework privado)

enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let fns: (get: GetFn, set: SetFn)? = {
        let url = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/DisplayServices.framework")
        guard let b = CFBundleCreate(kCFAllocatorDefault, url),
              let g = CFBundleGetFunctionPointerForName(b, "DisplayServicesGetBrightness" as CFString),
              let s = CFBundleGetFunctionPointerForName(b, "DisplayServicesSetBrightness" as CFString) else { return nil }
        return (unsafeBitCast(g, to: GetFn.self), unsafeBitCast(s, to: SetFn.self))
    }()

    /// A tela embutida (as teclas de brilho controlam ela).
    static var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    static var isAvailable: Bool { current() != nil }

    static func current() -> Float? {
        guard let fns else { return nil }
        var v: Float = 0
        return fns.get(display, &v) == 0 ? v : nil
    }

    static func step(up: Bool, fine: Bool) {
        guard let fns, let cur = current() else { return }
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        let snapped = (cur / step).rounded() * step
        _ = fns.set(display, min(1, max(0, snapped + (up ? step : -step))))
    }
}
