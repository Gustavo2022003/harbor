import AppKit
import CoreAudio
import IOBluetooth
import SwiftUI

/// Aparelhos Bluetooth conectados, bateria de cada um e se o som está saindo por Bluetooth.
/// A bateria vem do `system_profiler SPBluetoothDataType -json` (funciona com AirPods e com
/// fones de outras marcas que informam a bateria pelo HFP).
final class BluetoothMonitor: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String          // endereço
        var name: String
        var kind: String        // device_minorType (Headset, Headphones, Speaker, Keyboard…)
        var services: String
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?

        var isAudio: Bool {
            ["Headset", "Headphones", "Speaker", "Portable Audio", "Car Audio", "HiFi Audio", "Loudspeaker"]
                .contains(kind) || services.contains("A2DP") || name.lowercased().contains("airpods")
        }

        /// Menor bateria entre as partes que vão no corpo (ignora o estojo).
        var battery: Int? { [main, left, right].compactMap { $0 }.min() }

        var icon: String {
            let n = name.lowercased()
            if n.contains("airpods max") { return "airpodsmax" }
            if n.contains("airpods pro") { return "airpodspro" }
            if n.contains("airpods") { return "airpods" }
            if n.contains("beats") { return "beats.headphones" }
            switch kind {
            case "Headset", "Headphones": return "headphones"
            case "Speaker", "Portable Audio", "HiFi Audio", "Loudspeaker": return "hifispeaker.fill"
            case "Keyboard": return "keyboard.fill"
            case "Mouse": return "magicmouse.fill"
            case "Trackpad": return "rectangle.and.hand.point.up.left.fill"
            case "Gamepad", "Joystick": return "gamecontroller.fill"
            default: return isAudio ? "headphones" : "dot.radiowaves.left.and.right"
            }
        }

        /// Nome sem o "de Fulano" que o macOS acrescenta.
        var shortName: String {
            if let r = name.range(of: " de ", options: .backwards), r.lowerBound > name.startIndex {
                return String(name[..<r.lowerBound])
            }
            return name
        }
    }

    static let tint = Color(red: 0.39, green: 0.62, blue: 1)

    @Published private(set) var devices: [Device] = []
    /// O som do Mac está saindo por um aparelho Bluetooth.
    @Published private(set) var outputIsBluetooth = false
    @Published private(set) var outputName = ""

    var onAlert: ((NotchAlert) -> Void)?

    var audioDevices: [Device] { devices.filter(\.isAudio) }
    /// Aparelho principal para a bolha: o que está tocando o som, senão o primeiro fone/caixa.
    var primaryAudio: Device? {
        audioDevices.first { outputIsBluetooth && outputName.hasPrefix($0.shortName) } ?? audioDevices.first
    }

    private var timer: Timer?
    private var outputTimer: Timer?
    private var connectNote: IOBluetoothUserNotification?
    private var alerted: [String: Int] = [:]   // menor limiar já avisado por aparelho
    private var refreshing = false

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let o = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshOutput() }
        RunLoop.main.add(o, forMode: .common)
        outputTimer = o
        refreshOutput()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(changed(_:device:)))
    }

    @objc private func changed(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(changed(_:device:)))
        // a bateria demora um pouco para aparecer depois de conectar
        for delay in [1.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = Self.readDevices()
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                guard let list else { return }
                if list != self.devices { self.devices = list }
                self.checkBattery()
                self.refreshOutput()
            }
        }
    }

    // MARK: - Bateria fraca

    private func checkBattery() {
        let enabled = UserDefaults.standard.bool(forKey: AlertPrefs.bluetooth)
        for d in devices {
            guard let b = d.battery else { continue }
            if b > 25 { alerted.removeValue(forKey: d.id); continue }
            let level = b <= 10 ? 10 : b <= 20 ? 20 : nil
            guard let level, (alerted[d.id] ?? 100) > level else { continue }
            alerted[d.id] = level
            if enabled {
                onAlert?(NotchAlert(icon: d.icon, title: "\(d.shortName) · \(b)% de bateria", tint: .red))
            }
        }
    }

    // MARK: - system_profiler

    private static func readDevices() -> [Device]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else { return nil }
        let connected = bt["device_connected"] as? [[String: Any]] ?? []
        return connected.flatMap { entry in
            entry.compactMap { name, value -> Device? in
                guard let info = value as? [String: Any] else { return nil }
                func pct(_ key: String) -> Int? {
                    (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                }
                return Device(id: info["device_address"] as? String ?? name, name: name,
                              kind: info["device_minorType"] as? String ?? "",
                              services: info["device_services"] as? String ?? "",
                              main: pct("device_batteryLevelMain") ?? pct("device_batteryLevel"),
                              left: pct("device_batteryLevelLeft"), right: pct("device_batteryLevelRight"),
                              caseLevel: pct("device_batteryLevelCase"))
            }
        }
        .sorted { ($0.isAudio ? 0 : 1, $0.name) < ($1.isAudio ? 0 : 1, $1.name) }
    }

    // MARK: - Saída de áudio (CoreAudio)

    private func refreshOutput() {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr
        else { return }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyTransportType
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &transport)
        let isBT = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioObjectPropertyName
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name)
        let n = name?.takeRetainedValue() as String? ?? ""

        if isBT != outputIsBluetooth { outputIsBluetooth = isBT }
        if n != outputName { outputName = n }
    }
}
