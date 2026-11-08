import AppKit

/// Timer Pomodoro com modos Foco / Pausa.
final class FocusTimer: ObservableObject {
    enum Mode: String { case focus, pause }

    @Published private(set) var mode: Mode = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "timer.sound") } }
    @Published private(set) var focusMinutes: Int
    @Published private(set) var pauseMinutes: Int

    var onFinish: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var endDate: Date?
    private var ticker: Timer?

    init() {
        let d = UserDefaults.standard
        focusMinutes = d.object(forKey: "timer.focus") as? Int ?? 25
        pauseMinutes = d.object(forKey: "timer.pause") as? Int ?? 5
        soundEnabled = d.object(forKey: "timer.sound") as? Bool ?? true
        remaining = TimeInterval(focusMinutes * 60)
    }

    var selectedMinutes: Int { mode == .focus ? focusMinutes : pauseMinutes }
    var fullDuration: TimeInterval { TimeInterval(selectedMinutes * 60) }
    /// Timer rodando ou pausado no meio.
    var isActive: Bool { isRunning || (remaining > 0 && remaining < fullDuration - 0.5) }
    var hasProgress: Bool { remaining < fullDuration - 0.5 }
    var progress: Double { fullDuration > 0 ? 1 - remaining / fullDuration : 0 }

    var formatted: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func setMinutes(_ m: Int) {
        guard !isRunning else { return }
        if mode == .focus {
            focusMinutes = m
            defaults.set(m, forKey: "timer.focus")
        } else {
            pauseMinutes = m
            defaults.set(m, forKey: "timer.pause")
        }
        remaining = TimeInterval(m * 60)
    }

    func setMode(_ m: Mode) {
        guard m != mode else { return }
        focusSessionEnded()
        stopTicker()
        mode = m
        isRunning = false
        remaining = fullDuration
    }

    func toggle() { isRunning ? pause() : start() }

    // MARK: Integração com o Modo Foco do macOS (via app Atalhos)

    static let shortcutOnKey = "focus.shortcutOn"
    static let shortcutOffKey = "focus.shortcutOff"
    private var focusShortcutActive = false

    private func runShortcut(_ key: String) {
        guard let name = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
    }

    private func focusSessionBegan() {
        guard mode == .focus, !focusShortcutActive else { return }
        focusShortcutActive = true
        runShortcut(Self.shortcutOnKey)
    }

    private func focusSessionEnded() {
        guard focusShortcutActive else { return }
        focusShortcutActive = false
        runShortcut(Self.shortcutOffKey)
    }

    func start() {
        guard !isRunning, remaining > 0 else { return }
        focusSessionBegan()
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        isRunning = false
        stopTicker()
    }

    func reset() {
        focusSessionEnded()
        isRunning = false
        stopTicker()
        remaining = fullDuration
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    private func tick() {
        guard let end = endDate else { return }
        let r = max(0, end.timeIntervalSinceNow)
        if Int(r.rounded(.up)) != Int(remaining.rounded(.up)) { remaining = r }
        if r <= 0 { finish() }
    }

    private func finish() {
        focusSessionEnded()
        stopTicker()
        isRunning = false
        if soundEnabled { NSSound(named: "Glass")?.play() }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        mode = mode == .focus ? .pause : .focus
        remaining = fullDuration
        onFinish?()
    }
}
