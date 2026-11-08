import SwiftUI

// MARK: - Modelo do tema

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case album, solid, horizontal, vertical, rainbow
    var id: String { rawValue }

    var title: String {
        switch self {
        case .album: return "Capa"
        case .solid: return "Sólida"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .rainbow: return "Arco-íris"
        }
    }

    var icon: String {
        switch self {
        case .album: return "photo"
        case .solid: return "circle.fill"
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        case .rainbow: return "rainbow"
        }
    }

    var usesTwoColors: Bool { self == .horizontal || self == .vertical }
    var usesColors: Bool { self == .solid || usesTwoColors }
}

enum VizPrefs {
    static let style = "viz.style"
    static let color1 = "viz.color1"
    static let color2 = "viz.color2"
    static let intensity = "viz.intensity"
}

struct GradientPreset: Identifiable {
    let name: String
    let c1: String
    let c2: String
    var id: String { name }
}

enum VisualizerPresets {
    static let solids = ["FFFFFF", "FF9F0A", "FFD60A", "30D158", "64D2FF", "0A84FF", "BF5AF2", "FF375F"]

    static let gradients: [GradientPreset] = [
        .init(name: "Pôr do sol", c1: "FF9F0A", c2: "FF375F"),
        .init(name: "Oceano", c1: "64D2FF", c2: "0A5CFF"),
        .init(name: "Neon", c1: "30D158", c2: "64D2FF"),
        .init(name: "Uva", c1: "BF5AF2", c2: "FF375F"),
        .init(name: "Fogo", c1: "FFD60A", c2: "FF3B30"),
        .init(name: "Aurora", c1: "5EFCE8", c2: "736EFE"),
        .init(name: "Pêssego", c1: "FFB199", c2: "FF0844"),
        .init(name: "Gelo", c1: "FFFFFF", c2: "64D2FF"),
    ]
}

// MARK: - Visualizador

/// Barras animadas do áudio, coloridas conforme o tema escolhido em Ajustes.
struct AudioVisualizer: View {
    var isPlaying: Bool
    /// Cor extraída da capa (usada no estilo "Capa").
    var color: Color
    var bars = 4
    var barWidth: CGFloat = 2.6
    var spacing: CGFloat = 2.2
    var maxHeight: CGFloat = 16

    @AppStorage(VizPrefs.style) private var styleRaw = VisualizerStyle.album.rawValue
    @AppStorage(VizPrefs.color1) private var hex1 = "FF9F0A"
    @AppStorage(VizPrefs.color2) private var hex2 = "FF375F"

    @ObservedObject private var audio = AudioLevels.shared
    @AppStorage(VizPrefs.intensity) private var intensity = 1.4

    private var style: VisualizerStyle { VisualizerStyle(rawValue: styleRaw) ?? .album }
    private var totalWidth: CGFloat { CGFloat(bars) * barWidth + CGFloat(bars - 1) * spacing }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { ctx in
            fill(at: ctx.date)
                .frame(width: totalWidth, height: maxHeight)
                .mask {
                    HStack(spacing: spacing) {
                        ForEach(0..<bars, id: \.self) { i in
                            Capsule().frame(width: barWidth, height: height(i, ctx.date))
                        }
                    }
                    .frame(width: totalWidth, height: maxHeight)
                }
        }
        .frame(width: totalWidth, height: maxHeight)
    }

    @ViewBuilder
    private func fill(at date: Date) -> some View {
        switch style {
        case .album:
            Rectangle().fill(color)
        case .solid:
            Rectangle().fill(Color(hex: hex1))
        case .horizontal:
            LinearGradient(colors: [Color(hex: hex1), Color(hex: hex2)], startPoint: .leading, endPoint: .trailing)
        case .vertical:
            LinearGradient(colors: [Color(hex: hex1), Color(hex: hex2)], startPoint: .top, endPoint: .bottom)
        case .rainbow:
            let shift = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            LinearGradient(colors: (0...6).map { i in
                Color(hue: (Double(i) / 6 * 0.6 + shift).truncatingRemainder(dividingBy: 1),
                      saturation: 0.75, brightness: 1)
            }, startPoint: .leading, endPoint: .trailing)
        }
    }

    private func height(_ i: Int, _ date: Date) -> CGFloat {
        let minH = max(3, barWidth)
        guard isPlaying else { return minH }
        let v: Double
        if audio.isRunning {
            // Visualizador real: pico das bandas de frequência que caem nesta barra
            let n = audio.bands.count
            let a = i * n / bars, b = max(a + 1, (i + 1) * n / bars)
            v = Double(audio.bands[a..<min(b, n)].max() ?? 0)
        } else {
            v = Self.simulated(i, bars: bars, t: date.timeIntervalSinceReferenceDate)
        }
        return minH + CGFloat(exaggerate(v)) * (maxHeight - minH)
    }

    /// Aplica a intensidade escolhida em Ajustes (contraste em volta do meio + leve reforço).
    private func exaggerate(_ v: Double) -> Double {
        let k = intensity
        let boosted = pow(max(0, v), 1 / (0.6 + 0.4 * k)) // valores baixos sobem mais com k alto
        return min(1, max(0.03, 0.5 + (boosted - 0.5) * k))
    }

    /// Simulação "com batida": kick a ~124 BPM + variação rápida por barra.
    static func simulated(_ i: Int, bars: Int, t: Double) -> Double {
        let d = Double(i)
        let pos = bars > 1 ? d / Double(bars - 1) : 0          // 0 = grave, 1 = agudo
        let beat = 60.0 / 124.0
        let phase = t.truncatingRemainder(dividingBy: beat) / beat
        let kick = exp(-phase * 7)                              // ataque seco, queda rápida
        let offbeat = exp(-abs(phase - 0.5) * 18) * 0.5         // contratempo (chimbal)
        let n1 = sin(t * (9.7 + d * 3.1) + d * 1.9)
        let n2 = sin(t * (17.3 + d * 2.3) + d * 0.7)
        let n3 = sin(t * (4.1 + d * 0.9) + d * 2.6)
        var v = 0.28 + 0.2 * n1 + 0.14 * n2 + 0.1 * n3
        v += kick * (0.75 - 0.45 * pos)                         // grave pula mais na batida
        v += offbeat * (0.15 + 0.35 * pos)                      // agudo pula no contratempo
        return min(1, max(0, v))
    }
}

// MARK: - Cores em hexadecimal

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        func comp(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", comp(c.redComponent), comp(c.greenComponent), comp(c.blueComponent))
    }
}
