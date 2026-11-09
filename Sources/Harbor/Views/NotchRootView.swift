import SwiftUI

enum Theme {
    static let orange = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let green = Color(red: 0.42, green: 0.92, blue: 0.45)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.25)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.09)
    static let secondary = Color.white.opacity(0.55)
}

struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var shelf: ShelfStore
    @EnvironmentObject var odometer: MouseOdometer
    @EnvironmentObject var pins: AppPinStore
    @EnvironmentObject var mic: MicController
    @EnvironmentObject var media: MediaController
    @AppStorage(Prefs.liveGlow) private var liveGlow = true

    private let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        let open = vm.isOpen
        let body = vm.bodySize(open: open)
        let flare = vm.flare(open: open)

        VStack(spacing: vm.tabBarSpacing) {
            ZStack(alignment: .top) {
                if open {
                    OpenNotchView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(openSpring.delay(0.06)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))))
                } else {
                    ClosedNotchView()
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }
            }
            .frame(width: body.width, height: body.height, alignment: .top)
            .padding(.horizontal, flare)
            .modifier(IslandSurface(shape: NotchShape(topRadius: flare, bottomRadius: vm.bottomRadius(open: open)),
                                    glassVisible: open,
                                    glassRadius: vm.bottomRadius(open: true),
                                    glassInset: flare,
                                    extendsAboveTop: true,
                                    topShade: vm.notchSize.height + 8))
            .overlay(alignment: .topTrailing) {
                // Bolhas à direita do island: apps fixados e odômetro (somem/"são absorvidas" quando ele abre)
                if !open && (odometer.pinned || !pins.visible.isEmpty || mic.isMuted || mic.inUse) {
                    HStack(spacing: 5) {
                        if !pins.visible.isEmpty || mic.isMuted || mic.inUse {
                            PinnedAppBubbles()
                                .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                        }
                        if odometer.pinned {
                            OdometerBubble()
                                .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 3)
                    .padding(.leading, vm.bubbleGap)
                    // âncora de largura zero na borda direita: as bolhas "transbordam" para fora
                    .frame(width: 0, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                            .animation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.15)),
                        removal: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity)
                            .animation(.easeIn(duration: 0.15))))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: pins.visible)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: odometer.pinned)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: mic.isMuted)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: mic.inUse)
            .background(alignment: .top) {
                // Acabamento: notch fechado "vivo" com a música
                if liveGlow && !open && vm.closedActivity == .music {
                    LiveGlow(color: media.accent)
                        .padding(.horizontal, flare + 4)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(open ? 0.55 : 0), radius: 14, y: 4)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                vm.tab = .tray
                return shelf.handleDrop(providers)
            }

            if open {
                TabBarView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -12)).animation(openSpring.delay(0.08)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        // "Sugado" para dentro do notch / brota de volta
        .scaleEffect(x: vm.retracted ? 0.45 : 1, y: vm.retracted ? 0.02 : 1, anchor: .top)
        .blur(radius: vm.retracted ? 6 : 0)
        .opacity(vm.retracted ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(openSpring, value: vm.isOpen)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: vm.tab)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: vm.closedActivity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // O app nunca fica "ativo"; força a aparência ativa para o Liquid Glass não ficar apagado.
        .environment(\.appearsActive, true)
    }
}

// MARK: - Barra de abas

struct TabBarView: View {
    @EnvironmentObject var vm: NotchViewModel
    @Namespace private var ns

    /// Cor da aba "Agora": a da primeira atividade em execução.
    private var liveTint: Color { vm.live.first.map(LiveTabView.tint) ?? Theme.orange }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(vm.visibleTabs) { tab in
                let selected = vm.tab == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.tab = tab }
                } label: {
                    HStack(spacing: 6) {
                        if tab.isTemporary {
                            LiveDot(color: liveTint)
                        } else {
                            Image(systemName: tab.icon)
                        }
                        if selected || tab.isTemporary { Text(tab.title) }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tab.isTemporary ? liveTint : (selected ? Color.white : Color.white.opacity(0.6)))
                    .padding(.horizontal, selected ? 16 : 11)
                    .frame(height: vm.tabBarHeight - 8)
                    .background {
                        if selected {
                            Capsule().fill(Color.white.opacity(0.14))
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .overlay {
                        if tab.isTemporary && !selected {
                            Capsule().strokeBorder(liveTint.opacity(0.45))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.live)
        .padding(4)
        .frame(height: vm.tabBarHeight)
        .modifier(IslandSurface(shape: Capsule(), glassVisible: true, glassRadius: vm.tabBarHeight / 2))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

// MARK: - Conteúdo aberto

struct OpenNotchView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.notchSize.height)
            Group {
                switch vm.tab {
                case .live: LiveTabView()
                case .nook: NookHomeView()
                case .media: MediaTabView()
                case .clipboard: ClipboardTabView()
                case .prs: PRsTabView()
                case .calendar: CalendarTabView()
                case .tray: TrayTabView()
                case .camera: CameraTabView()
                case .odometer: OdometerTabView()
                case .tools: ToolsTabView()
                case .settings: SettingsTabView()
                }
            }
            .id(vm.tab)
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
    }
}
