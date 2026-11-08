import AppKit
import CoreAudio
import IOBluetooth
import IOKit.ps
import SwiftUI

/// Aviso rápido mostrado no notch fechado (estilo Dynamic Island).
struct NotchAlert: Equatable {
    var id = UUID()
    var icon: String
    var title: String
    /// Nível 0...1 (volume/brilho) — mostra uma barra em vez de texto.
    var level: Double?
    var tint: Color = .white
}

enum AlertPrefs {
    static let volume = "alert.volume"
    static let brightness = "alert.brightness"
    static let power = "alert.power"
    static let bluetooth = "alert.bluetooth"

    static func register() {
        UserDefaults.standard.register(defaults: [volume: true, brightness: true, power: true, bluetooth: true])
    }
}

/// Fila de avisos + fontes: volume, brilho, energia e Bluetooth.
final class AlertCenter: NSObject, ObservableObject {
    @Published private(set) var current: NotchAlert?

    private var hideWork: DispatchWorkItem?
    private var lastVolume: Float?
    private var lastMuted: Bool?
    private var lastBrightness: Float?
    private var brightnessTimer: Timer?
    private var wasOnAC: Bool?
    private var warnedLow: Set<Int> = []
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var powerSource: CFRunLoopSource?
    private var btNotification: IOBluetoothUserNotification?
    private let defaults = UserDefaults.standard

    func start() {
        AlertPrefs.register()
        startVolume()
        startBrightness()
        startPower()
        startBluetooth()
    }

    /// Mostra um aviso por `duration` segundos (substitui o atual).
    func show(_ alert: NotchAlert, duration: TimeInterval = 2.2) {
        hideWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { current = alert }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { self?.current = nil }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    // MARK: - Volume (CoreAudio)

    private func startVolume() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            self?.attachToDefaultOutput()
        }
        attachToDefaultOutput()
    }

    private func attachToDefaultOutput() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != outputDevice else { return }
        outputDevice = id
        lastVolume = readVolume()
        lastMuted = readMuted()
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in [kAudioObjectPropertyElementMain, 1] {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                   mElement: element)
                if AudioObjectHasProperty(id, &a) {
                    AudioObjectAddPropertyListenerBlock(id, &a, .main) { [weak self] _, _ in self?.volumeChanged() }
                }
            }
        }
    }

    private func readVolume() -> Float? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(outputDevice, &a),
               AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &v) == noErr { return v }
        }
        return nil
    }

    private func readMuted() -> Bool {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(outputDevice, &a),
              AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &v) == noErr else { return false }
        return v != 0
    }

    private func volumeChanged() {
        let v = readVolume() ?? 0
        let muted = readMuted()
        defer { lastVolume = v; lastMuted = muted }
        guard defaults.bool(forKey: AlertPrefs.volume),
              abs(v - (lastVolume ?? v)) > 0.001 || muted != lastMuted else { return }
        let icon: String
        if muted || v < 0.01 { icon = "speaker.slash.fill" }
        else if v < 0.34 { icon = "speaker.wave.1.fill" }
        else if v < 0.67 { icon = "speaker.wave.2.fill" }
        else { icon = "speaker.wave.3.fill" }
        show(NotchAlert(icon: icon, title: "Volume", level: muted ? 0 : Double(v)), duration: 1.6)
    }

    // MARK: - Brilho (DisplayServices — framework privado)

    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private lazy var getBrightness: GetBrightnessFn? = {
        let url = NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/DisplayServices.framework")
        guard let b = CFBundleCreate(kCFAllocatorDefault, url),
              let p = CFBundleGetFunctionPointerForName(b, "DisplayServicesGetBrightness" as CFString) else { return nil }
        return unsafeBitCast(p, to: GetBrightnessFn.self)
    }()

    private func startBrightness() {
        guard getBrightness != nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollBrightness() }
        RunLoop.main.add(t, forMode: .common)
        brightnessTimer = t
    }

    func pollBrightness() {
        guard let getBrightness else { return }
        var b: Float = 0
        guard getBrightness(DisplayBrightness.display, &b) == 0 else { return }
        defer { lastBrightness = b }
        guard let last = lastBrightness, abs(b - last) > 0.004,
              defaults.bool(forKey: AlertPrefs.brightness) else { return }
        show(NotchAlert(icon: b < 0.5 ? "sun.min.fill" : "sun.max.fill", title: "Brilho",
                        level: Double(b), tint: Theme.yellow), duration: 1.6)
    }

    // MARK: - Energia

    private func startPower() {
        readPower(initial: true)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<AlertCenter>.fromOpaque(ctx).takeUnretainedValue().readPower(initial: false)
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
    }

    private func readPower(initial: Bool) {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = max > 0 ? Int(Double(cur) / Double(max) * 100) : 0
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            defer { wasOnAC = onAC }
            guard !initial, defaults.bool(forKey: AlertPrefs.power) else { return }
            if let was = wasOnAC, was != onAC {
                show(onAC
                     ? NotchAlert(icon: "bolt.fill", title: "Carregando · \(pct)%", tint: Theme.green)
                     : NotchAlert(icon: "powerplug", title: "Na bateria · \(pct)%"), duration: 2.4)
            }
            if onAC { warnedLow.removeAll() }
            for threshold in [20, 10] where !onAC && pct <= threshold && !warnedLow.contains(threshold) {
                warnedLow.insert(threshold)
                show(NotchAlert(icon: "battery.25percent", title: "Bateria fraca · \(pct)%", tint: .red), duration: 3.5)
            }
            return
        }
    }

    // MARK: - Bluetooth (fones/AirPods)

    private func startBluetooth() {
        btNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                    selector: #selector(btConnected(_:device:)))
    }

    @objc private func btConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(btDisconnected(_:device:)))
        // Ignora dispositivos que já estavam conectados quando o app abriu
        guard defaults.bool(forKey: AlertPrefs.bluetooth),
              ProcessInfo.processInfo.systemUptime > 20,
              Date().timeIntervalSince(launchDate) > 5 else { return }
        let name = device.name ?? "Dispositivo"
        let isAudio = device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio)
        let lower = name.lowercased()
        let icon = lower.contains("airpods max") ? "airpodsmax"
            : lower.contains("airpods pro") ? "airpodspro"
            : lower.contains("airpods") ? "airpods"
            : isAudio ? "headphones" : "dot.radiowaves.left.and.right"
        var title = name
        if let b = Self.batteryPercent(device) { title += " · \(b)%" }
        show(NotchAlert(icon: icon, title: title, tint: Color(red: 0.4, green: 0.75, blue: 1)), duration: 3)
    }

    @objc private func btDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard defaults.bool(forKey: AlertPrefs.bluetooth),
              device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) else { return }
        show(NotchAlert(icon: "headphones", title: "\(device.name ?? "Fone") desconectado"), duration: 2)
    }

    private let launchDate = Date()

    /// Bateria de fones Apple (propriedade não documentada; retorna nil se indisponível).
    private static func batteryPercent(_ d: IOBluetoothDevice) -> Int? {
        for key in ["batteryPercentCombined", "batteryPercentSingle", "batteryPercentLeft"] {
            let sel = NSSelectorFromString(key)
            if d.responds(to: sel), let v = d.value(forKey: key) as? Int, v > 0 { return v }
        }
        return nil
    }
}
