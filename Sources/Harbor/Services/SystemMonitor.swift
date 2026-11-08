import Foundation
import Darwin
import IOKit.ps

/// CPU e bateria com histórico para os gráficos.
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var battery: Double = 0
    @Published private(set) var batteryHistory: [Double] = []
    @Published private(set) var isCharging = false
    @Published private(set) var hasBattery = true
    /// Bytes por segundo.
    @Published private(set) var netDown: Double = 0
    @Published private(set) var netUp: Double = 0
    @Published private(set) var netDownHistory: [Double] = []
    @Published private(set) var netUpHistory: [Double] = []
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?

    private let historySize = 40
    private var prevTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var timer: Timer?

    func start() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        if let c = readCPU() {
            cpu = c
            cpuHistory.append(c)
            if cpuHistory.count > historySize { cpuHistory.removeFirst(cpuHistory.count - historySize) }
        }
        readBattery()
        readNetwork()
        batteryHistory.append(battery)
        if batteryHistory.count > historySize { batteryHistory.removeFirst(batteryHistory.count - historySize) }
    }

    private func readNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let flags = Int32(cur.pointee.ifa_flags)
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                let name = String(cString: cur.pointee.ifa_name)
                // interfaces físicas (en*) — ignora túneis/bridges para não contar em dobro
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                }
            }
            p = cur.pointee.ifa_next
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0 {
                netDown = rx >= last.rx ? Double(rx - last.rx) / dt : 0
                netUp = tx >= last.tx ? Double(tx - last.tx) / dt : 0
                netDownHistory.append(netDown)
                netUpHistory.append(netUp)
                if netDownHistory.count > historySize { netDownHistory.removeFirst(netDownHistory.count - historySize) }
                if netUpHistory.count > historySize { netUpHistory.removeFirst(netUpHistory.count - historySize) }
            }
        }
        lastNet = (rx, tx, now)
    }

    static func formatRate(_ bytesPerSec: Double) -> String {
        let bits = bytesPerSec * 8
        if bits < 1_000 { return String(format: "%.0f b/s", bits) }
        if bits < 1_000_000 { return String(format: "%.0f Kb/s", bits / 1_000) }
        if bits < 1_000_000_000 { return String(format: "%.1f Mb/s", bits / 1_000_000) }
        return String(format: "%.2f Gb/s", bits / 1_000_000_000)
    }

    private func readCPU() -> Double? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { prevTicks = t }
        guard let p = prevTicks else { return nil }
        let user = Double(t.user &- p.user)
        let sys = Double(t.system &- p.system)
        let idle = Double(t.idle &- p.idle)
        let nice = Double(t.nice &- p.nice)
        let total = user + sys + idle + nice
        guard total > 0 else { return nil }
        return (user + sys + nice) / total * 100
    }

    private func readBattery() {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(snap, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            battery = max > 0 ? Double(cur) / Double(max) * 100 : 0
            isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                || (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            hasBattery = true
            return
        }
        hasBattery = false
    }
}
