import SwiftUI

enum NookTab: String, CaseIterable, Identifiable {
    case live, nook, media, clipboard, prs, calendar, tray, camera, odometer, tools, settings
    var id: String { rawValue }

    /// Aba temporária: só existe enquanto há algo em execução.
    var isTemporary: Bool { self == .live }

    var title: String {
        switch self {
        case .live: return "Agora"
        case .nook: return "Início"
        case .media: return "Mídia"
        case .clipboard: return "Copiados"
        case .prs: return "PRs"
        case .calendar: return "Agenda"
        case .tray: return "Bandeja"
        case .camera: return "Espelho"
        case .odometer: return "Odômetro"
        case .tools: return "Ferramentas"
        case .settings: return "Ajustes"
        }
    }

    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .nook: return "rectangle.topthird.inset.filled"
        case .media: return "play.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .prs: return "arrow.triangle.pull"
        case .calendar: return "calendar"
        case .tray: return "tray.fill"
        case .camera: return "camera.fill"
        case .odometer: return "computermouse.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .settings: return "sparkles"
        }
    }
}

/// Atividades em execução que ganham um cartão na aba temporária "Agora".
enum LiveKind: Equatable {
    case claude, download, timer, meeting
}

/// O que aparece nas "asas" do notch fechado.
enum ClosedActivity: Equatable {
    case none, music, timer, claude, meeting, download, alert
}

final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NookTab = .nook {
        willSet {
            // Lembra onde o usuário estava para voltar quando a aba temporária "Agora" fechar
            if newValue == .live && tab != .live { tabBeforeLive = tab == .camera ? .nook : tab }
        }
    }
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var closedActivity: ClosedActivity = .none
    /// Mantém o notch aberto mesmo com o mouse fora (ex.: digitando uma tarefa).
    @Published var keepOpen = false
    /// Recolhido para dentro do notch (tela cheia / troca de tela / entrada do app).
    @Published var retracted = false
    /// O que está em execução agora (ordem de exibição). Vazio → a aba "Agora" some.
    @Published var live: [LiveKind] = []
    /// Aba em que o usuário estava antes de a aba "Agora" abrir sozinha.
    var tabBeforeLive: NookTab = .nook

    /// Abas mostradas na barra (a temporária só enquanto há algo rodando).
    var visibleTabs: [NookTab] {
        NookTab.allCases.filter { !$0.isTemporary || !live.isEmpty }
    }

    /// Tamanho da área de conteúdo quando aberto (abaixo da faixa do notch).
    let openContentSize = CGSize(width: 960, height: 150)
    let tabBarHeight: CGFloat = 38
    let tabBarSpacing: CGFloat = 8

    var makeKey: (() -> Void)?

    /// Bolha ao lado do island (ex.: odômetro fixado).
    let bubbleGap: CGFloat = 6
    @Published var bubbleWidth: CGFloat = 0
    @Published var leftBubblesWidth: CGFloat = 0

    func flare(open: Bool) -> CGFloat { open ? 16 : 6 }
    func bottomRadius(open: Bool) -> CGFloat { open ? 30 : 11 }

    /// Largura extra de cada lado quando há atividade no notch fechado.
    var activityWing: CGFloat {
        switch closedActivity {
        case .none: return 0
        case .alert: return 128
        case .meeting: return 78
        case .download: return 72
        // "12m05s" não cabe na asa padrão: alarga para o tempo não encostar na borda
        case .claude: return 70
        default: return notchSize.height + 16
        }
    }

    /// Pedido de foco em um campo (ex.: atalho ⌥V foca a busca do histórico).
    enum FocusTarget: Equatable { case clipboardSearch, note }
    @Published var focusRequest: FocusTarget?

    /// Tamanho do "corpo" (sem as abas laterais curvas do topo).
    func bodySize(open: Bool) -> CGSize {
        if open { return openBodySize(for: tab) }
        let wing: CGFloat = closedActivity == .none ? 0 : activityWing
        return CGSize(width: notchSize.width + wing * 2, height: notchSize.height)
    }

    /// Lado da câmera 1:1 na aba Espelho.
    let cameraSide: CGFloat = 240
    /// Altura da linha de controles abaixo da câmera.
    let cameraControlsHeight: CGFloat = 30

    /// Na aba Espelho o island vira um retângulo vertical; nas demais, horizontal.
    func openBodySize(for tab: NookTab) -> CGSize {
        if tab == .camera {
            // padding do OpenNotchView: 14 laterais, 2 topo, 14 base; 8 entre câmera e controles
            return CGSize(width: max(cameraSide + 28, notchSize.width + 40),
                          height: notchSize.height + 2 + cameraSide + 8 + cameraControlsHeight + 14)
        }
        return CGSize(width: openContentSize.width, height: notchSize.height + openContentSize.height)
    }

    /// Tamanho total desenhado pela NotchShape.
    func shapeSize(open: Bool) -> CGSize {
        let b = bodySize(open: open)
        return CGSize(width: b.width + flare(open: open) * 2, height: b.height)
    }

    /// Maior formato aberto possível (para dimensionar a janela).
    var maxOpenShapeSize: CGSize {
        let sizes = NookTab.allCases.map { openBodySize(for: $0) }
        return CGSize(width: (sizes.map(\.width).max() ?? 0) + flare(open: true) * 2,
                      height: sizes.map(\.height).max() ?? 0)
    }

    /// Largura aproximada da barra de abas (para a área de hover).
    let tabBarWidthEstimate: CGFloat = 560
}
