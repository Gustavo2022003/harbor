import AppKit
import SwiftUI
import Combine

/// Orquestra a janela do notch, o rastreamento do mouse, atalhos e os serviços.
final class NotchController {
    let vm = NotchViewModel()
    let media = MediaController()
    let system = SystemMonitor()
    let timer = FocusTimer()
    let tasks = TaskStore()
    let shelf = ShelfStore()
    let calendar = CalendarStore()
    let camera = CameraManager()
    let clipboard = ClipboardStore()
    let odometer = MouseOdometer()
    let alerts = AlertCenter()
    let claude = ClaudeActivity()
    let colorPicker = ColorPickerStore()
    let audio = AudioLevels.shared
    let keys = MediaKeyInterceptor()
    let pins = AppPinStore()
    let mic = MicController()

    private var panel: NotchPanel!
    private var screen: NSScreen!
    private var trackTimer: Timer?
    private var tick = 0
    private var hoverStart: Date?
    private var exitStart: Date?
    private var mouseWasDown = false
    private var dragChangeCount = 0
    private var pinned = false
    /// Aberto por atalho: só fecha com Esc, atalho, clique fora ou ao sair depois de entrar.
    private var sticky = false
    private var pinnedAt = Date()
    private var hiddenForFullscreen = false
    /// Durante a troca animada de tela.
    private var transitioning = false
    private var alertedMeetings = Set<String>()
    private var hotKeys: HotKeys?
    private var monitors: [Any] = []

    private var openDelay: Double { UserDefaults.standard.double(forKey: Prefs.openDelay) }

    func start() {
        Prefs.registerDefaults()
        media.start()
        system.start()
        clipboard.start()
        odometer.start()
        alerts.start()
        keys.onBrightnessChange = { [weak self] in self?.alerts.pollBrightness() }
        clipboard.closeNotch = { [weak self] in self?.close() }

        claude.onAlert = { [weak self] a in self?.alerts.show(a, duration: 4) }
        pins.onAlert = { [weak self] a in self?.alerts.show(a, duration: 1.8) }
        mic.onAlert = { [weak self] a in self?.alerts.show(a, duration: 1.6) }
        mic.start()
        timer.onFinish = { [weak self] in
            guard let self else { return }
            let focusEnded = self.timer.mode == .pause // já trocou de modo
            self.alerts.show(NotchAlert(icon: focusEnded ? "checkmark.circle.fill" : "cup.and.saucer.fill",
                                        title: focusEnded ? "Foco concluído! Hora da pausa" : "Pausa concluída",
                                        tint: Theme.orange), duration: 4)
        }
        colorPicker.onPicked = { [weak self] hex in
            self?.alerts.show(NotchAlert(icon: "eyedropper.full", title: "\(hex) copiado", tint: Color(hex: hex)))
        }

        vm.makeKey = { [weak self] in self?.panel.makeKey() }

        layout()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.pickScreen() != self.screen { self.moveToScreenAnimated() } else { self.layout() }
        }

        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
            return
        }

        // Entrada: o island "brota" do notch ao abrir o app
        vm.retracted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.setRetracted(false) }

        // Detecta tela cheia na hora em que o Space ou o app da frente mudam
        let wnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.checkFullscreen() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.checkFullscreen() }
            }
        }

        setupHotKeys()
        setupEventMonitors()
        keys.start()

        trackTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(trackTimer!, forMode: .common)
    }

    func handle(url: URL) {
        claude.handle(url: url)
    }

    // MARK: - Atalhos e monitores

    private func setupHotKeys() {
        let hk = HotKeys()
        hk.register(HotKeys.toggle) { [weak self] in
            guard let self else { return }
            if self.vm.isOpen { self.close() } else { self.openFromShortcut(tab: nil, focus: nil) }
        }
        hk.register(HotKeys.clipboard) { [weak self] in
            self?.openFromShortcut(tab: .clipboard, focus: .clipboardSearch)
        }
        hk.register(HotKeys.note) { [weak self] in
            self?.openFromShortcut(tab: .tools, focus: .note)
        }
        hk.register(HotKeys.mic) { [weak self] in
            self?.mic.toggle()
        }
        hk.register(HotKeys.pinApp) { [weak self] in
            self?.pins.toggleFrontmost()
        }
        hk.register(HotKeys.picker) { [weak self] in
            self?.colorPicker.pick()
        }
        hotKeys = hk
    }

    private func openFromShortcut(tab: NookTab?, focus: NotchViewModel.FocusTarget?) {
        if hiddenForFullscreen { setRetracted(false) }
        open(tab: tab, pinned: true)
        sticky = true
        panel.makeKey()
        if let focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.vm.focusRequest = focus }
        }
    }

    private func setupEventMonitors() {
        // Esc fecha o island
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self, self.vm.isOpen, e.keyCode == 53 else { return e }
            if self.vm.keepOpen { return e } // deixa o campo de texto tratar o Esc primeiro
            self.close()
            return nil
        }) { monitors.append(m) }

        // Clique fora fecha (útil quando aberto por atalho)
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, self.vm.isOpen, !self.vm.keepOpen,
                  !(NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible),
                  !self.openRect().contains(NSEvent.mouseLocation) else { return }
            self.close()
        }) { monitors.append(m) }
    }

    /// Depuração: renderiza cada estado da janela em PNG e encerra.
    private func snapshot(to dir: String) {
        let states: [(String, Bool, NookTab)] = NookTab.allCases.map { ($0.rawValue, true, $0) }
            .map { $0.0 == "nook" ? ("nook", true, NookTab.nook) : $0 }
        let all = [("closed", false, NookTab.nook)] + states
        func shoot(_ idx: Int) {
            guard idx < all.count else { NSApp.terminate(nil); return }
            let (name, open, tab) = all[idx]
            vm.tab = tab
            vm.isOpen = open
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.vm.closedActivity = self.computeActivity() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                guard let view = self.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
                shoot(idx + 1)
            }
        }
        shoot(0)
    }

    // MARK: - Layout / telas

    private func pickScreen() -> NSScreen {
        let mode = ScreenMode(rawValue: UserDefaults.standard.string(forKey: Prefs.screenMode) ?? "") ?? .notch
        switch mode {
        case .main:
            return NSScreen.main ?? NSScreen.screens[0]
        case .mouse:
            let p = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.screens[0]
        case .notch:
            return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        }
    }

    private func layout() {
        screen = pickScreen()
        let f = screen.frame

        var notch = CGSize(width: 200, height: max(24, f.maxY - screen.visibleFrame.maxY))
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: f.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        vm.notchSize = notch

        let open = vm.maxOpenShapeSize
        let w = max(open.width, vm.tabBarWidthEstimate) + 80
        let h = open.height + vm.tabBarSpacing + vm.tabBarHeight + 40
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)

        if panel == nil {
            panel = NotchPanel(contentRect: rect)
            let root = NotchRootView()
                .environmentObject(vm)
                .environmentObject(media)
                .environmentObject(system)
                .environmentObject(timer)
                .environmentObject(tasks)
                .environmentObject(shelf)
                .environmentObject(calendar)
                .environmentObject(camera)
                .environmentObject(clipboard)
                .environmentObject(odometer)
                .environmentObject(alerts)
                .environmentObject(claude)
                .environmentObject(colorPicker)
                .environmentObject(audio)
                .environmentObject(keys)
                .environmentObject(pins)
                .environmentObject(mic)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: rect.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
        }
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
    }

    // MARK: - Hit areas (coordenadas de tela)

    private func closedRect() -> NSRect {
        let f = screen.frame
        let s = vm.shapeSize(open: false)
        let w = s.width + 16
        let h = s.height + 6
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 1)
    }

    /// Área da bolha (à direita do island fechado).
    private func bubbleRect() -> NSRect? {
        guard odometer.pinned, vm.bubbleWidth > 0 else { return nil }
        let f = screen.frame
        let s = vm.shapeSize(open: false)
        // depois das bolhas de apps fixados, se houver
        let apps = hasClickableBubbles ? vm.leftBubblesWidth + 5 : 0
        let x = f.midX + s.width / 2 + vm.bubbleGap + apps
        let h = vm.notchSize.height
        return NSRect(x: x - 2, y: f.maxY - h, width: vm.bubbleWidth + 6, height: h + 1)
    }

    /// Bolhas clicáveis à direita: microfone (em uso ou mudo) e apps fixados.
    private var hasClickableBubbles: Bool { mic.isMuted || mic.inUse || !pins.visible.isEmpty }

    /// Área das bolhas clicáveis (logo à direita do island fechado).
    private func leftBubblesRect() -> NSRect? {
        guard hasClickableBubbles, vm.leftBubblesWidth > 0 else { return nil }
        let f = screen.frame
        let s = vm.shapeSize(open: false)
        let minX = f.midX + s.width / 2 + vm.bubbleGap
        let h = vm.notchSize.height
        return NSRect(x: minX - 2, y: f.maxY - h, width: vm.leftBubblesWidth + 4, height: h + 1)
    }

    private func openRect() -> NSRect {
        let f = screen.frame
        let s = vm.shapeSize(open: true)
        let w = max(s.width, vm.tabBarWidthEstimate) + 24
        let h = s.height + vm.tabBarSpacing + vm.tabBarHeight + 18
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 1)
    }

    // MARK: - O que mostrar no notch fechado

    private func computeActivity() -> ClosedActivity {
        if alerts.current != nil { return .alert }
        if let m = calendar.nextMeeting, m.start.timeIntervalSinceNow < 10 * 60 { return .meeting }
        if claude.workingSession != nil { return .claude }
        if media.info?.isPlaying == true { return .music }
        if timer.isActive { return .timer }
        return .none
    }

    private func periodicChecks() {
        // Visualizador real: liga/desliga captura de áudio
        audio.update(musicPlaying: media.info?.isPlaying == true)

        // Aviso 1 min antes da reunião
        if let m = calendar.nextMeeting, !alertedMeetings.contains(m.id) {
            let dt = m.start.timeIntervalSinceNow
            if dt <= 60 && dt > -30 {
                alertedMeetings.insert(m.id)
                alerts.show(NotchAlert(icon: "video.fill", title: "\(m.title) começa já", tint: m.color), duration: 5)
            }
        }

        checkFullscreen()

        // Modo "seguir o mouse": troca de tela
        if UserDefaults.standard.string(forKey: Prefs.screenMode) == ScreenMode.mouse.rawValue, !vm.isOpen {
            if pickScreen() != screen { moveToScreenAnimated() }
        }
    }

    // MARK: - Animações de saída/entrada

    /// Ocultar quando um app está em tela cheia (o island "é sugado" para o notch).
    private func checkFullscreen() {
        guard screen != nil, !transitioning else { return }
        let hide = UserDefaults.standard.bool(forKey: Prefs.hideInFullscreen) && !vm.isOpen
            && frontAppIsFullscreen(on: screen)
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        setRetracted(hide)
    }

    /// Recolhe para dentro do notch (ou brota de volta com quique).
    private func setRetracted(_ retract: Bool, completion: (() -> Void)? = nil) {
        if retract {
            withAnimation(.easeIn(duration: 0.28)) { vm.retracted = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                guard let self else { return }
                if self.vm.retracted { self.panel.alphaValue = 0 }
                completion?()
            }
        } else {
            panel.alphaValue = 1
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { vm.retracted = false }
            completion?()
        }
    }

    /// Troca de tela: recolhe na tela atual, move e brota na nova.
    private func moveToScreenAnimated() {
        guard !transitioning, panel != nil else { layout(); return }
        transitioning = true
        close()
        setRetracted(true) { [weak self] in
            guard let self else { return }
            self.layout()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.transitioning = false
                self.hiddenForFullscreen = false
                self.checkFullscreen()
                if !self.hiddenForFullscreen { self.setRetracted(false) }
            }
        }
    }

    private func frontAppIsFullscreen(on screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryH = NSScreen.screens[0].frame.height
        let f = screen.frame
        let cg = CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
        let notchH = screen.safeAreaInsets.top
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { continue }
            let sameWidth = abs(r.width - cg.width) < 1 && abs(r.minX - cg.minX) < 1
            let sameBottom = abs(r.maxY - cg.maxY) < 1
            let topOK = abs(r.minY - cg.minY) < 1 || (notchH > 0 && abs(r.minY - (cg.minY + notchH)) < 1)
            if sameWidth && sameBottom && topOK { return true }
        }
        return false
    }

    // MARK: - Tracking

    private func track() {
        guard screen != nil else { return }
        tick += 1
        if tick % 3 == 0 {
            let act = computeActivity()
            if act != vm.closedActivity {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { vm.closedActivity = act }
            }
        }
        if tick % 30 == 0 { periodicChecks() }
        if hiddenForFullscreen || transitioning || vm.retracted { return }

        let p = NSEvent.mouseLocation
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let dragPB = NSPasteboard(name: .drag)
        if down && !mouseWasDown { dragChangeCount = dragPB.changeCount }
        mouseWasDown = down
        let draggingFile = down && dragPB.changeCount != dragChangeCount

        if !vm.isOpen {
            // Bolhas de apps fixados: aceitam clique só enquanto o mouse está sobre elas
            if let lb = leftBubblesRect(), lb.contains(p) {
                if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
                hoverStart = nil
                return
            } else if !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
            }
            if let b = bubbleRect(), b.contains(p), !down {
                if hoverStart == nil { hoverStart = Date() }
                if Date().timeIntervalSince(hoverStart!) >= openDelay { open(tab: .odometer) }
                return
            }
            if closedRect().contains(p) {
                if draggingFile {
                    open(tab: .tray)
                    return
                }
                if hoverStart == nil { hoverStart = Date() }
                if !down, Date().timeIntervalSince(hoverStart!) >= openDelay {
                    // Com reunião próxima, abre direto na Agenda
                    open(tab: vm.closedActivity == .meeting ? .calendar : nil)
                }
            } else {
                hoverStart = nil
            }
        } else {
            if openRect().contains(p) {
                exitStart = nil
                pinned = false
                ensureKeyForGlass()
            } else {
                if vm.keepOpen { return }
                // Mantém aberto enquanto o seletor de cores (Ajustes › Tema) estiver na tela.
                if NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible { return }
                if pinned {
                    if !sticky && Date().timeIntervalSince(pinnedAt) > 5 { close() }
                    return
                }
                if exitStart == nil { exitStart = Date() }
                if Date().timeIntervalSince(exitStart!) > 0.12 { close() }
            }
        }
    }

    func open(tab: NookTab?, pinned: Bool = false) {
        if let tab { vm.tab = tab }
        self.pinned = pinned
        sticky = false
        pinnedAt = Date()
        exitStart = nil
        hoverStart = nil
        guard !vm.isOpen else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { vm.isOpen = true }
        panel.ignoresMouseEvents = false
        ensureKeyForGlass()
        if UserDefaults.standard.bool(forKey: Prefs.haptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// O Liquid Glass do sistema só renderiza completo (lente/refração) na janela em foco.
    /// O painel não ativa o app, então o app da frente continua ativo; ao fechar, o foco volta para ele.
    private func ensureKeyForGlass() {
        guard UserDefaults.standard.string(forKey: AppearancePrefs.appearance) == IslandAppearance.glass.rawValue,
              !panel.isKeyWindow,
              !(NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible) else { return }
        panel.makeKey()
    }

    func close() {
        guard vm.isOpen else { return }
        let wasKey = panel.isKeyWindow
        vm.keepOpen = false
        sticky = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { vm.isOpen = false }
        panel.ignoresMouseEvents = true
        if hiddenForFullscreen { setRetracted(true) }
        exitStart = nil
        hoverStart = Date.distantFuture // evita reabrir imediatamente
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.hoverStart = nil
            // A aba Espelho não "gruda": ao sair com o mouse, a próxima abertura volta para a primeira aba.
            if !self.vm.isOpen && self.vm.tab == .camera {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { self.vm.tab = .nook }
            }
        }
        if wasKey {
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }
}

enum ScreenMode: String, CaseIterable, Identifiable {
    case notch, main, mouse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notch: return "Com notch"
        case .main: return "Principal"
        case .mouse: return "Seguir mouse"
        }
    }
}

enum Prefs {
    static let openDelay = "openDelay"
    static let haptics = "haptics"
    static let showVisualizer = "showVisualizer"
    static let screenMode = "screenMode"
    static let hideInFullscreen = "hideInFullscreen"
    static let liveGlow = "liveGlow"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            openDelay: 0.15,
            haptics: true,
            showVisualizer: true,
            screenMode: ScreenMode.notch.rawValue,
            hideInFullscreen: true,
            liveGlow: true,
        ])
    }
}
