import AppKit
import SwiftUI

/// Modo limpeza: bloqueia teclado, trackpad e mouse para limpar o MacBook.
/// Sai segurando o botão do mouse (ou o clique do trackpad) por `holdToUnlock` segundos.
///
/// - Um event tap no nível HID engole **todos** os eventos (teclas, mídia, movimento, cliques, rolagem, gestos).
/// - O cursor fica parado (`CGAssociateMouseAndMouseCursorPosition`) e, por garantia, volta ao lugar se mexer.
/// - Segurança: destrava sozinho depois de `safetyTimeout`. Se o Harbor fechar, o macOS solta o tap na hora.
/// - Precisa da permissão de Acessibilidade (a mesma do aviso de volume/brilho).
final class CleaningMode: ObservableObject {
    static let holdToUnlock: TimeInterval = 3.5
    static let safetyTimeout: TimeInterval = 5 * 60

    @Published private(set) var active = false
    /// 0…1 enquanto o botão está pressionado.
    @Published private(set) var holdProgress: Double = 0
    @Published private(set) var startedAt = Date()

    var onAlert: ((NotchAlert) -> Void)?
    /// Chamado ao ativar (para fechar o island antes de bloquear).
    var willStart: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdStart: Date?
    private var holdTimer: Timer?
    private var safetyTimer: Timer?
    private var cursor = CGPoint.zero
    private var windows: [NSWindow] = []

    // MARK: - Ligar / desligar

    func start() {
        guard !active else { return }
        guard AXIsProcessTrusted() else {
            onAlert?(NotchAlert(icon: "hand.raised.fill", title: "Modo limpeza precisa da Acessibilidade", tint: .red))
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            return
        }
        willStart?()
        // Pequena pausa: o clique que ativou termina antes do bloqueio
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.engage() }
    }

    private func engage() {
        guard !active, installTap() else {
            if tap == nil {
                onAlert?(NotchAlert(icon: "exclamationmark.triangle.fill", title: "Não foi possível bloquear a entrada", tint: .red))
            }
            return
        }
        cursor = CGEvent(source: nil)?.location ?? .zero
        CGAssociateMouseAndMouseCursorPosition(0)
        startedAt = Date()
        holdProgress = 0
        active = true
        showOverlay()
        let s = Timer(timeInterval: Self.safetyTimeout, repeats: false) { [weak self] _ in self?.stop() }
        RunLoop.main.add(s, forMode: .common)
        safetyTimer = s
    }

    func stop() {
        guard active else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        holdTimer?.invalidate(); holdTimer = nil
        safetyTimer?.invalidate(); safetyTimer = nil
        holdStart = nil
        active = false
        holdProgress = 0
        hideOverlay()
        onAlert?(NotchAlert(icon: "keyboard.fill", title: "Teclado e trackpad liberados", tint: Theme.green))
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        // Todos os tipos de evento (teclas, NX_SYSDEFINED, mouse, rolagem, gestos)
        let mask = CGEventMask.max
        guard let t = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CleaningMode>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            beginHold()
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            cancelHold()
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            // Garantia: se o cursor andar, volta para onde estava
            CGWarpMouseCursorPosition(cursor)
        default:
            break
        }
        return nil // engole tudo
    }

    // MARK: - Segurar para sair

    private func beginHold() {
        guard holdStart == nil else { return }
        holdStart = Date()
        holdTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let s = self.holdStart else { return }
            let p = min(1, Date().timeIntervalSince(s) / Self.holdToUnlock)
            self.holdProgress = p
            if p >= 1 { self.stop() }
        }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    private func cancelHold() {
        holdStart = nil
        holdTimer?.invalidate(); holdTimer = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { holdProgress = 0 }
    }

    // MARK: - Camada sobre as telas

    private func showOverlay() {
        hideOverlay()
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.animationBehavior = .none
            let host = NSHostingView(rootView: CleaningOverlay(mode: self, primary: screen == NSScreen.main))
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            w.contentView = host
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; w.animator().alphaValue = 1 }
            windows.append(w)
        }
    }

    private func hideOverlay() {
        let ws = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; ws.forEach { $0.animator().alphaValue = 0 } },
                                            completionHandler: { ws.forEach { $0.orderOut(nil) } })
    }
}

/// Tela do modo limpeza: escurece tudo e mostra como sair.
struct CleaningOverlay: View {
    @ObservedObject var mode: CleaningMode
    var primary: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
            if primary {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                        Circle().trim(from: 0, to: mode.holdProgress)
                            .stroke(Theme.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: mode.holdProgress > 0 ? "lock.open.fill" : "keyboard.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 120, height: 120)
                    Text("Modo limpeza").font(.system(size: 30, weight: .bold))
                    Text("Teclado, trackpad e mouse estão bloqueados. Pode limpar à vontade.")
                        .font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.75))
                    Text(mode.holdProgress > 0 ? "Continue segurando…" : "Para sair, segure o clique por 3,5 segundos")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(Capsule().fill(Theme.orange.opacity(0.15)))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let left = max(0, CleaningMode.safetyTimeout - ctx.date.timeIntervalSince(mode.startedAt))
                        Text("Destrava sozinho em \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))")
                            .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
