import AppKit
import CoreAudio

/// Mudo global do microfone (entrada padrão) + detecção de "microfone em uso".
/// Usa a propriedade Mute da entrada quando existe; senão, zera o volume de entrada e restaura depois.
final class MicController: ObservableObject {
    @Published private(set) var isMuted = false
    /// Algum app está usando o microfone agora.
    @Published private(set) var inUse = false

    var onAlert: ((NotchAlert) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var savedVolume: Float32?
    private var timer: Timer?
    private let savedKey = "mic.savedVolume"

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.attach()
        }
        attach()
        // Se o app fechou com o microfone mudo por volume, restaura
        if let v = UserDefaults.standard.object(forKey: savedKey) as? Float {
            setVolume(v)
            UserDefaults.standard.removeObject(forKey: savedKey)
        }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    func toggle() { setMuted(!isMuted) }

    func setMuted(_ mute: Bool) {
        guard device != kAudioObjectUnknown else { return }
        if hasSettableMute {
            var v: UInt32 = mute ? 1 : 0
            var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        } else if mute {
            savedVolume = currentVolume() ?? 1
            UserDefaults.standard.set(savedVolume, forKey: savedKey)
            setVolume(0)
        } else {
            setVolume(savedVolume ?? 1)
            savedVolume = nil
            UserDefaults.standard.removeObject(forKey: savedKey)
        }
        refresh()
        onAlert?(mute
                 ? NotchAlert(icon: "mic.slash.fill", title: "Microfone mudo", tint: .red)
                 : NotchAlert(icon: "mic.fill", title: "Microfone ativo", tint: Theme.green))
    }

    /// Chamado ao encerrar o app: não deixa o microfone "preso" no mudo.
    func restoreOnQuit() {
        if isMuted { setMuted(false) }
    }

    // MARK: - CoreAudio

    private func attach() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        let wasMuted = isMuted
        device = id
        // Mantém o estado ao trocar de microfone (ex.: conectou AirPods)
        if wasMuted { setMuted(true) }
        refresh()
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }

    private var hasSettableMute: Bool {
        var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &a)
            && AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
    }

    private var volumeElements: [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { el in
            var a = address(kAudioDevicePropertyVolumeScalar, el)
            var settable: DarwinBoolean = false
            return AudioObjectHasProperty(device, &a)
                && AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
        }
    }

    private func currentVolume() -> Float32? {
        guard let el = volumeElements.first else { return nil }
        var a = address(kAudioDevicePropertyVolumeScalar, el)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func setVolume(_ value: Float32) {
        var v = value
        for el in volumeElements {
            var a = address(kAudioDevicePropertyVolumeScalar, el)
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    private func refresh() {
        guard device != kAudioObjectUnknown else { return }
        // Mudo?
        var muted = false
        if hasSettableMute {
            var a = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr { muted = v != 0 }
        } else {
            muted = savedVolume != nil
        }
        // Em uso por algum app?
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var r = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &r, 0, nil, &size, &running)

        if muted != isMuted { isMuted = muted }
        if (running != 0) != inUse { inUse = running != 0 }
    }
}
