import SwiftUI

enum IslandAppearance: String, CaseIterable, Identifiable {
    case solid, glass
    var id: String { rawValue }
    var title: String { self == .solid ? "Preto" : "Liquid Glass" }
    var icon: String { self == .solid ? "circle.fill" : "drop.fill" }
}

enum GlassVariant: String, CaseIterable, Identifiable {
    /// Transparente, com a distorção (lente) forte nas bordas.
    case clear
    /// Fosco, mais desfoque e menos distorção.
    case regular
    var id: String { rawValue }
    var title: String { self == .clear ? "Transparente" : "Fosco" }
}

/// Quem desenha o vidro: o `glassEffect` do SwiftUI ou o `NSGlassEffectView` nativo do AppKit.
enum GlassEngine: String, CaseIterable, Identifiable {
    /// Refração real (captura de tela + shader Metal). Exige Gravação de Tela.
    case refraction
    case appkit, swiftui
    var id: String { rawValue }
    var title: String {
        switch self {
        case .refraction: return "Refração"
        case .appkit: return "AppKit"
        case .swiftui: return "SwiftUI"
        }
    }
}

enum AppearancePrefs {
    static let appearance = "appearance"
    static let glassDim = "glassDim"
    static let glassVariant = "glassVariant"
    static let glassEngine = "glassEngine"
}

/// Fundo do island: preto sólido ou Liquid Glass.
/// Fechado, fica sempre preto para se fundir ao notch físico; aberto, o preto some e revela o vidro.
struct IslandSurface<S: Shape>: ViewModifier {
    var shape: S
    /// Quando `true` (island aberto), o vidro aparece se a aparência for Liquid Glass.
    var glassVisible: Bool
    /// Raio dos cantos do vidro nativo (AppKit só aceita raio uniforme).
    var glassRadius: CGFloat
    /// Recuo lateral do vidro nativo (as "abas" curvas do topo do notch ficam de fora).
    var glassInset: CGFloat = 0
    /// Estende o vidro nativo acima da janela para esconder os cantos de cima (encostados no topo da tela).
    var extendsAboveTop: Bool = false
    /// Altura da faixa do topo escurecida no modo vidro (esconde a barra de menus atrás do island).
    var topShade: CGFloat = 0

    @AppStorage(AppearancePrefs.appearance) private var appearanceRaw = IslandAppearance.solid.rawValue
    @AppStorage(AppearancePrefs.glassDim) private var dim = 0.3
    @AppStorage(AppearancePrefs.glassVariant) private var variantRaw = GlassVariant.clear.rawValue
    @AppStorage(AppearancePrefs.glassEngine) private var engineRaw = GlassEngine.refraction.rawValue

    private var glassOn: Bool { appearanceRaw == IslandAppearance.glass.rawValue && glassVisible }
    private var variant: GlassVariant { GlassVariant(rawValue: variantRaw) ?? .clear }
    private var engine: GlassEngine { GlassEngine(rawValue: engineRaw) ?? .refraction }

    func body(content: Content) -> some View {
        content
            .background {
                // Preto sólido sem vidro; com vidro, nada por cima para não apagar a refração.
                shape.fill(Color.black).opacity(glassOn ? 0 : 1)
            }
            .background(alignment: .top) {
                if glassOn && topShade > 0 {
                    LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0),
                                           .init(color: .black.opacity(0.6), location: 0.6),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: topShade + 14)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .modifier(SwiftUIGlass(shape: shape,
                                   enabled: glassOn && engine == .swiftui,
                                   variant: variant, dim: dim))
            .background {
                ZStack {
                    // Vidro nativo — sem máscara, para manter a lente nas bordas.
                    // No motor Refração ele é a base enquanto a captura não chega (ou sem permissão).
                    if engine == .appkit || engine == .refraction {
                        NativeGlass(variant: variant, dim: dim, cornerRadius: glassRadius)
                            .padding(.horizontal, glassInset)
                            .padding(.top, extendsAboveTop ? -(glassRadius + 20) : 0)
                            .opacity(glassOn ? 1 : 0)
                    }
                    // Refração real (captura + shader), por cima da base nativa.
                    if engine == .refraction && glassOn {
                        RefractionGlass(inset: glassInset, radius: glassRadius,
                                        topExtend: extendsAboveTop ? glassRadius + 20 : 0, dim: dim)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay {
                // Aro de brilho: borda clara de vidro (border 1px rgba(255,255,255,.25) + reflexos).
                if glassOn {
                    shape
                        .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.1), .white.opacity(0.3)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                        .mask {
                            // No island, some perto do topo (que encosta na borda da tela).
                            LinearGradient(stops: [.init(color: extendsAboveTop ? .clear : .black, location: 0),
                                                   .init(color: .black, location: extendsAboveTop ? 0.35 : 0)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: glassOn)
    }
}

// MARK: - SwiftUI glassEffect

private struct SwiftUIGlass<S: Shape>: ViewModifier {
    var shape: S
    var enabled: Bool
    var variant: GlassVariant
    var dim: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        guard enabled else { return .identity }
        let base: Glass = variant == .clear ? .clear : .regular
        return dim > 0.01 ? base.tint(Color.black.opacity(dim)) : base
    }
}

// MARK: - AppKit NSGlassEffectView

private struct NativeGlass: NSViewRepresentable {
    var variant: GlassVariant
    var dim: Double
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let v = NSGlassEffectView()
            apply(to: v)
            return v
        }
        // Fallback para macOS 14/15: desfoque clássico.
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let v = nsView as? NSGlassEffectView {
            apply(to: v)
        } else {
            nsView.layer?.cornerRadius = cornerRadius
        }
    }

    @available(macOS 26.0, *)
    private func apply(to v: NSGlassEffectView) {
        v.style = variant == .clear ? .clear : .regular
        v.cornerRadius = cornerRadius
        v.tintColor = dim > 0.01 ? NSColor.black.withAlphaComponent(dim) : nil
    }
}
