import AppKit
import ApplicationServices

/// Apps fixados: quando não estão na frente, aparecem como bolhas à direita do notch.
final class AppPinStore: ObservableObject {
    struct PinnedApp: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let icon: NSImage
        var id: String { bundleID }
        static func == (a: PinnedApp, b: PinnedApp) -> Bool { a.bundleID == b.bundleID }
    }

    /// Ordem em que foram fixados.
    @Published private(set) var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pins.apps") ?? []
    /// Bolhas visíveis agora: fixados, abertos e que não estão na frente.
    @Published private(set) var visible: [PinnedApp] = []
    /// Badges do Dock (ex.: "3") por bundle ID — lidos via Acessibilidade.
    @Published private(set) var badges: [String: String] = [:]
    private var badgeTimer: Timer?

    var onAlert: ((NotchAlert) -> Void)?

    private var frontmostID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier { self?.frontmostID = id }
            self?.recompute()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.recompute() }
        }
        recompute()
    }

    func isPinned(_ bundleID: String) -> Bool { pinned.contains(bundleID) }

    // MARK: - Badges do Dock

    func startBadges() {
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refreshBadges() }
        RunLoop.main.add(t, forMode: .common)
        badgeTimer = t
        refreshBadges()
    }

    private func refreshBadges() {
        guard !pinned.isEmpty, AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { if !badges.isEmpty { badges = [:] }; return }

        func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
        }

        var found: [String: String] = [:]
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let lists = (attr(app, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        for list in lists {
            for item in (attr(list, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                guard let label = attr(item, "AXStatusLabel") as? String, !label.isEmpty else { continue }
                var id: String?
                if let url = attr(item, kAXURLAttribute) as? URL {
                    id = Bundle(url: url)?.bundleIdentifier
                }
                if id == nil, let title = attr(item, kAXTitleAttribute) as? String {
                    id = pinned.first { Self.info($0)?.name == title }
                }
                if let id, pinned.contains(id) { found[id] = label }
            }
        }
        if found != badges { badges = found }
    }

    /// ⌥P: fixa/desafixa o app que está na frente.
    func toggleFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
        let name = app.localizedName ?? id
        if isPinned(id) {
            unpin(id)
            onAlert?(NotchAlert(icon: "pin.slash.fill", title: "\(name) desafixado"))
        } else {
            pin(id)
            onAlert?(NotchAlert(icon: "pin.fill", title: "\(name) fixado", tint: Theme.orange))
        }
    }

    func pin(_ bundleID: String) {
        guard !pinned.contains(bundleID) else { return }
        pinned.append(bundleID)
        save()
    }

    func unpin(_ bundleID: String) {
        pinned.removeAll { $0 == bundleID }
        save()
    }

    /// Traz o app para a frente (como clicar no Dock — funciona mesmo com o Harbor em segundo plano).
    func activate(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// Apps abertos que podem ser fixados (para a lista em Ajustes).
    var runningCandidates: [PinnedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { $0.bundleIdentifier.flatMap(Self.info) }
            .filter { !isPinned($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var pinnedInfo: [PinnedApp] { pinned.compactMap(Self.info) }

    static func info(_ bundleID: String) -> PinnedApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return PinnedApp(bundleID: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    private func recompute() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let v = pinned
            .filter { running.contains($0) && $0 != frontmostID }
            .compactMap(Self.info)
        if v != visible { visible = v }
    }

    private func save() {
        UserDefaults.standard.set(pinned, forKey: "pins.apps")
        recompute()
    }
}
