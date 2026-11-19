import AppKit
import CoreAudio
import SwiftUI

/// Detecta chamadas em andamento (Meet, Teams, Zoom, FaceTime, Slack, Discord…) sem permissão extra:
/// o CoreAudio informa **qual processo está usando o microfone** (`kAudioProcessPropertyIsRunningInput`).
/// - App nativo de chamada usando o microfone → é a chamada.
/// - Navegador usando o microfone → o serviço vem do título da janela (quando o macOS libera os títulos)
///   ou da reunião da Agenda que está acontecendo agora (link do Meet/Teams/Zoom…).
final class CallMonitor: ObservableObject {
    struct Provider: Equatable {
        let name: String
        let color: Color
        /// Domínio do serviço web (para o ícone quando a chamada é no navegador).
        let domain: String?
    }

    struct Call: Equatable {
        var provider: Provider
        var title: String?
        var appBundleID: String       // app a ativar (o navegador ou o app nativo)
        var pid: pid_t
        var since: Date
        var inBrowser: Bool
    }

    @Published private(set) var call: Call?
    /// Ícone do serviço/app da chamada atual.
    @Published private(set) var icon: NSImage?

    /// Agenda (reunião acontecendo agora) para identificar o serviço no navegador.
    var currentMeeting: (() -> DayEvent?)?
    var onAlert: ((NotchAlert) -> Void)?

    private var timer: Timer?
    private var missing = 0
    private var iconCache: [String: NSImage] = [:]

    static let meet = Provider(name: "Google Meet", color: Color(red: 0.0, green: 0.68, blue: 0.47), domain: "meet.google.com")
    static let teams = Provider(name: "Microsoft Teams", color: Color(red: 0.38, green: 0.39, blue: 0.85), domain: "teams.microsoft.com")
    static let zoom = Provider(name: "Zoom", color: Color(red: 0.17, green: 0.55, blue: 1.0), domain: "zoom.us")
    static let generic = Provider(name: "Chamada", color: Theme.green, domain: nil)

    /// Apps nativos de chamada (prefixo do bundle id → serviço).
    private static let nativeApps: [(String, Provider)] = [
        ("us.zoom.xos", zoom),
        ("com.microsoft.teams", teams),
        ("com.apple.FaceTime", Provider(name: "FaceTime", color: Theme.green, domain: nil)),
        ("com.tinyspeck.slackmacgap", Provider(name: "Slack", color: Color(red: 0.88, green: 0.12, blue: 0.35), domain: "slack.com")),
        ("com.hnc.Discord", Provider(name: "Discord", color: Color(red: 0.35, green: 0.40, blue: 0.95), domain: "discord.com")),
        ("Cisco-Systems.Spark", Provider(name: "Webex", color: Color(red: 0.0, green: 0.7, blue: 0.4), domain: "webex.com")),
        ("com.cisco.webex", Provider(name: "Webex", color: Color(red: 0.0, green: 0.7, blue: 0.4), domain: "webex.com")),
        ("net.whatsapp.WhatsApp", Provider(name: "WhatsApp", color: Color(red: 0.15, green: 0.83, blue: 0.4), domain: "whatsapp.com")),
        ("com.apple.TelephonyUtilities", Provider(name: "Chamada", color: Theme.green, domain: nil)),
    ]

    private static let browsers = ["com.google.Chrome", "com.apple.Safari", "com.apple.WebKit", "company.thebrowser.Browser",
                                   "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox",
                                   "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]

    func start() {
        // No --snapshot fica a chamada fictícia (a detecção real a apagaria)
        guard timer == nil, !CommandLine.arguments.contains("--snapshot") else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Chamada fictícia para o `--snapshot`.
    func injectDemo() {
        call = Call(provider: Self.meet, title: "Daily do time", appBundleID: "com.google.Chrome", pid: 0,
                    since: Date().addingTimeInterval(-754), inBrowser: true)
        icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        loadIcon(for: Self.meet, appBundleID: "com.google.Chrome")
    }

    /// Volta para a janela da chamada.
    func activate() {
        guard let c = call else { return }
        let app = NSRunningApplication(processIdentifier: c.pid)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: c.appBundleID).first
        app?.activate()
    }

    // MARK: - Detecção

    private func refresh() {
        let users = Self.inputProcesses()
        var found: Call?
        for (bundle, pid) in users {
            if let p = Self.nativeApps.first(where: { bundle.hasPrefix($0.0) }) {
                let main = Self.mainApp(for: bundle, pid: pid)
                found = Call(provider: p.1, title: currentMeeting?()?.title, appBundleID: main.bundle,
                             pid: main.pid, since: Date(), inBrowser: false)
                break
            }
            if let browser = Self.browsers.first(where: { bundle.hasPrefix($0) }) {
                let main = Self.mainApp(for: browser, pid: pid)
                let (provider, title) = identifyWeb(pid: main.pid)
                found = Call(provider: provider, title: title, appBundleID: main.bundle,
                             pid: main.pid, since: Date(), inBrowser: true)
                break
            }
        }

        if var f = found {
            missing = 0
            if let c = call, c.appBundleID == f.appBundleID {
                f.since = c.since
                if f.provider == Self.generic && c.provider != Self.generic { f.provider = c.provider }
                if f.title == nil { f.title = c.title }
            }
            if f != call {
                if call?.provider != f.provider || call?.appBundleID != f.appBundleID {
                    loadIcon(for: f.provider, appBundleID: f.appBundleID)
                }
                call = f
            }
        } else if call != nil {
            // tolera falhas curtas (troca de microfone, mudo por hardware)
            missing += 1
            if missing >= 3 { call = nil; icon = nil; missing = 0 }
        }
    }

    /// Serviço e título de uma chamada no navegador.
    private func identifyWeb(pid: pid_t) -> (Provider, String?) {
        // 1. Título da janela (precisa da Gravação de Tela para os títulos de outros apps)
        for title in Self.windowTitles(pid: pid) {
            let t = title.lowercased()
            if t.contains("meet") { return (Self.meet, Self.cleanTitle(title)) }
            if t.contains("teams") { return (Self.teams, Self.cleanTitle(title)) }
            if t.contains("zoom") { return (Self.zoom, Self.cleanTitle(title)) }
        }
        // 2. Reunião da Agenda acontecendo agora, pelo link
        if let m = currentMeeting?(), let host = m.link?.host?.lowercased() {
            if host.contains("meet.google") { return (Self.meet, m.title) }
            if host.contains("teams.") { return (Self.teams, m.title) }
            if host.contains("zoom.us") { return (Self.zoom, m.title) }
            return (Self.generic, m.title)
        }
        return (Self.generic, nil)
    }

    private static func cleanTitle(_ t: String) -> String? {
        var s = t
        for junk in [" - Google Chrome", " – Google Chrome", " - Brave", " - Microsoft Edge", " — Mozilla Firefox",
                     "Meet - ", "Meet – ", " | Microsoft Teams", "Microsoft Teams"] {
            s = s.replacingOccurrences(of: junk, with: "")
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty || s.lowercased() == "meet" ? nil : s
    }

    private static func windowTitles(pid: pid_t) -> [String] {
        guard pid > 0, let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            (w[kCGWindowOwnerPID as String] as? pid_t) == pid ? w[kCGWindowName as String] as? String : nil
        }.filter { !$0.isEmpty }
    }

    /// App principal de um processo auxiliar (ex.: com.google.Chrome.helper → com.google.Chrome).
    private static func mainApp(for bundle: String, pid: pid_t) -> (bundle: String, pid: pid_t) {
        let apps = NSWorkspace.shared.runningApplications
        // Safari grava pelo processo com.apple.WebKit.GPU
        if bundle.hasPrefix("com.apple.WebKit"),
           let safari = apps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
            return ("com.apple.Safari", safari.processIdentifier)
        }
        if let exact = apps.first(where: { $0.processIdentifier == pid && $0.activationPolicy == .regular }) {
            return (exact.bundleIdentifier ?? bundle, pid)
        }
        if let main = apps.filter({ $0.activationPolicy == .regular })
            .first(where: { ($0.bundleIdentifier).map { bundle.hasPrefix($0) } ?? false }) {
            return (main.bundleIdentifier ?? bundle, main.processIdentifier)
        }
        return (bundle, pid)
    }

    /// (bundle id, pid) dos processos que estão gravando do microfone agora.
    private static func inputProcesses() -> [(String, pid_t)] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        func prop<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ v: inout T) -> Bool {
            var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var s = UInt32(MemoryLayout<T>.size)
            return AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr
        }
        return ids.compactMap { id in
            var running: UInt32 = 0
            guard prop(id, kAudioProcessPropertyIsRunningInput, &running), running != 0 else { return nil }
            var pid: pid_t = 0
            _ = prop(id, kAudioProcessPropertyPID, &pid)
            var bid: Unmanaged<CFString>?
            _ = prop(id, kAudioProcessPropertyBundleID, &bid)
            guard let b = bid?.takeRetainedValue() as String?, !b.isEmpty else { return nil }
            return (b, pid)
        }
    }

    // MARK: - Ícone

    /// App nativo: ícone do app. Serviço web: favicon do serviço (baixado uma vez); até lá, o ícone do navegador.
    private func loadIcon(for p: Provider, appBundleID: String) {
        let appIcon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        let isBrowser = Self.browsers.contains { appBundleID.hasPrefix($0) }
        guard isBrowser, let domain = p.domain else { icon = appIcon; return }
        if let cached = iconCache[domain] { icon = cached; return }
        icon = appIcon
        let cacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.gustavo.harbor/icons/\(domain).png")
        if let img = NSImage(contentsOf: cacheFile) { iconCache[domain] = img; icon = img; return }
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data), img.size.width >= 32 else { return }
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile)
            DispatchQueue.main.async {
                guard let self else { return }
                self.iconCache[domain] = img
                if self.call?.provider.domain == domain { self.icon = img }
            }
        }.resume()
    }
}
