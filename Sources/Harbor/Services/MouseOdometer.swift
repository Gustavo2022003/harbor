import AppKit

enum DistanceUnit: String, CaseIterable, Identifiable {
    case metric, imperial, football, banana
    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Métrico"
        case .imperial: return "Imperial"
        case .football: return "⚽ Campos"
        case .banana: return "🍌 Bananas"
        }
    }
}

/// Mede quanto o cursor anda na tela, convertido em distância física real
/// (usando o tamanho físico de cada monitor em milímetros).
final class MouseOdometer: ObservableObject {
    @Published private(set) var todayMeters: Double = 0
    @Published private(set) var totalMeters: Double = 0
    /// Velocidade suavizada, em metros por segundo.
    @Published private(set) var speed: Double = 0
    @Published var unit: DistanceUnit {
        didSet { defaults.set(unit.rawValue, forKey: Keys.unit) }
    }
    /// Mostra a bolha ao lado do island com a distância de hoje.
    @Published var pinned: Bool {
        didSet { defaults.set(pinned, forKey: Keys.pinned) }
    }

    private enum Keys {
        static let today = "odo.today"
        static let total = "odo.total"
        static let day = "odo.day"
        static let unit = "odo.unit"
        static let pinned = "odo.pinned"
    }

    private let defaults = UserDefaults.standard
    private var lastPoint: NSPoint?
    private var timer: Timer?
    private var tick = 0
    private var pendingToday: Double = 0
    private var pendingTotal: Double = 0
    private var recentMeters: Double = 0
    private var day: String
    private var mmPerPointCache: [CGDirectDisplayID: CGFloat] = [:]

    init() {
        unit = DistanceUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .metric
        pinned = defaults.bool(forKey: Keys.pinned)
        totalMeters = defaults.double(forKey: Keys.total)
        day = Self.dayKey()
        todayMeters = defaults.string(forKey: Keys.day) == day ? defaults.double(forKey: Keys.today) : 0
        pendingToday = todayMeters
        pendingTotal = totalMeters
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.mmPerPointCache.removeAll()
        }
    }

    func start() {
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func resetToday() {
        pendingToday = 0
        todayMeters = 0
        save()
    }

    func resetAll() {
        pendingToday = 0
        pendingTotal = 0
        todayMeters = 0
        totalMeters = 0
        save()
    }

    // MARK: - Amostragem

    private func sample() {
        let p = NSEvent.mouseLocation
        defer { lastPoint = p }
        tick += 1

        if let last = lastPoint {
            let dx = p.x - last.x, dy = p.y - last.y
            let points = (dx * dx + dy * dy).squareRoot()
            // Ignora "teletransportes" (ex.: cursor reposicionado por software)
            if points > 0, points < 3000 {
                let meters = Double(points * mmPerPoint(at: p)) / 1000
                pendingToday += meters
                pendingTotal += meters
                recentMeters += meters
            }
        }

        // Publica a 10 Hz (suficiente para o número "rolar" sem pesar)
        if tick % 3 == 0 {
            let today = Self.dayKey()
            if today != day {
                day = today
                pendingToday = 0
            }
            if pendingToday != todayMeters { todayMeters = pendingToday }
            if pendingTotal != totalMeters { totalMeters = pendingTotal }
            let instant = recentMeters / 0.1
            recentMeters = 0
            let s = speed * 0.7 + instant * 0.3
            speed = s < 0.0005 ? 0 : s
        }
        if tick % 150 == 0 { save() } // a cada ~5 s
    }

    private func mmPerPoint(at p: NSPoint) -> CGFloat {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) ?? NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return 0.2 }
        if let c = mmPerPointCache[id] { return c }
        let size = CGDisplayScreenSize(id) // milímetros
        // Fallback: ~110 pontos por polegada se o monitor não informar o tamanho
        let v = size.width > 0 ? size.width / screen.frame.width : 25.4 / 110
        mmPerPointCache[id] = v
        return v
    }

    private func save() {
        defaults.set(pendingToday, forKey: Keys.today)
        defaults.set(pendingTotal, forKey: Keys.total)
        defaults.set(day, forKey: Keys.day)
    }

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Formatação

    private static func number(_ v: Double, _ digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Valor e sufixo separados (para o número grande + unidade pequena).
    func parts(_ meters: Double) -> (value: String, suffix: String) {
        switch unit {
        case .metric:
            if meters < 1 { return (Self.number(meters * 100, 1), "cm") }
            if meters < 1000 { return (Self.number(meters, 2), "m") }
            return (Self.number(meters / 1000, 3), "km")
        case .imperial:
            let feet = meters * 3.28084
            if feet < 1 { return (Self.number(feet * 12, 1), "in") }
            if feet < 5280 { return (Self.number(feet, 1), "ft") }
            return (Self.number(feet / 5280, 3), "mi")
        case .football:
            return (Self.number(meters / 105, 2), meters / 105 >= 2 ? "campos" : "campo")
        case .banana:
            return (Self.number(meters / 0.18, 0), "bananas")
        }
    }

    func format(_ meters: Double) -> String {
        let p = parts(meters)
        return "\(p.value) \(p.suffix)"
    }

    func formatSpeed(_ mps: Double) -> String {
        switch unit {
        case .imperial: return Self.number(mps * 3.28084, 2) + " ft/s"
        case .banana: return Self.number(mps / 0.18, 1) + " 🍌/s"
        default: return Self.number(mps, 2) + " m/s"
        }
    }

    /// Comparação divertida para a distância total.
    func comparison(_ meters: Double) -> String {
        let landmarks: [(String, Double)] = [
            ("a maratona", 42_195),
            ("a Ponte Rio–Niterói", 13_290),
            ("o Burj Khalifa", 828),
            ("a Torre Eiffel", 330),
            ("o Cristo Redentor", 38),
            ("uma piscina olímpica", 50),
        ].sorted { $0.1 > $1.1 }
        if let (name, size) = landmarks.first(where: { meters >= $0.1 }) {
            return "≈ \(Self.number(meters / size, 1))× \(name)"
        }
        return "≈ \(Self.number(meters / 0.18, 0)) bananas enfileiradas"
    }
}
