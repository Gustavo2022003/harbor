import SwiftUI
import ServiceManagement

struct SettingsTabView: View {
    @EnvironmentObject var media: MediaController

    @AppStorage(Prefs.openDelay) private var openDelay = 0.15
    @AppStorage(Prefs.haptics) private var haptics = true
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true
    @AppStorage(VizPrefs.style) private var styleRaw = VisualizerStyle.album.rawValue
    @AppStorage(VizPrefs.color1) private var hex1 = "FF9F0A"
    @AppStorage(VizPrefs.color2) private var hex2 = "FF375F"
    @AppStorage(AppearancePrefs.appearance) private var appearanceRaw = IslandAppearance.solid.rawValue
    @AppStorage(AppearancePrefs.glassDim) private var glassDim = 0.3
    @AppStorage(AppearancePrefs.glassVariant) private var glassVariant = GlassVariant.clear.rawValue
    @AppStorage(AppearancePrefs.glassEngine) private var glassEngine = GlassEngine.refraction.rawValue
    @AppStorage(BackdropCapture.blurKey) private var glassBlur = 12.0
    @ObservedObject private var backdrop = BackdropCapture.shared
    @Local private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("settings.section") private var sectionRaw = SettingsSection.general.rawValue
    @AppStorage(AudioLevels.modeKey) private var realVisualizer = false
    @AppStorage(VizPrefs.intensity) private var vizIntensity = 1.4
    @AppStorage(Prefs.screenMode) private var screenMode = ScreenMode.notch.rawValue
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = true
    @AppStorage(Prefs.liveGlow) private var liveGlow = true
    @AppStorage(AlertPrefs.volume) private var alertVolume = true
    @AppStorage(AlertPrefs.brightness) private var alertBrightness = true
    @AppStorage(AlertPrefs.power) private var alertPower = true
    @AppStorage(AlertPrefs.bluetooth) private var alertBluetooth = true
    @AppStorage(FocusTimer.shortcutOnKey) private var focusOn = ""
    @AppStorage(FocusTimer.shortcutOffKey) private var focusOff = ""
    @EnvironmentObject var claude: ClaudeActivity
    @EnvironmentObject var keys: MediaKeyInterceptor
    @EnvironmentObject var pins: AppPinStore
    @AppStorage(MediaKeyInterceptor.enabledKey) private var replaceHUD = true
    @EnvironmentObject var vm: NotchViewModel
    @Local private var claudeError = ""
    @FocusState private var fieldFocused: Bool

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, visual, integrations, pins, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "Geral"
            case .visual: return "Visual"
            case .integrations: return "Integrações"
            case .pins: return "Apps fixados"
            case .about: return "Sobre"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .visual: return "paintpalette.fill"
            case .integrations: return "puzzlepiece.extension.fill"
            case .pins: return "pin.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    private var style: VisualizerStyle { VisualizerStyle(rawValue: styleRaw) ?? .album }
    private var section: SettingsSection { SettingsSection(rawValue: sectionRaw) ?? .general }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sidebar.frame(width: 122)
            ModuleDivider()
            Group {
                switch section {
                case .general:
                    HStack(alignment: .top, spacing: 14) {
                        behaviorColumn.frame(width: 206, alignment: .leading)
                        ModuleDivider()
                        screenColumn.frame(width: 176, alignment: .leading)
                        ModuleDivider()
                        alertsColumn.frame(width: 160, alignment: .leading)
                        ModuleDivider()
                        shortcutsColumn.frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .visual:
                    HStack(alignment: .top, spacing: 14) {
                        themeColumn.frame(maxWidth: .infinity, alignment: .leading)
                        ModuleDivider()
                        appearanceColumn.frame(width: 232)
                    }
                case .pins:
                    pinsSection
                case .about:
                    aboutSection
                case .integrations:
                    HStack(alignment: .top, spacing: 14) {
                        claudeColumn.frame(maxWidth: .infinity, alignment: .leading)
                        ModuleDivider()
                        hudColumn.frame(width: 200, alignment: .leading)
                        ModuleDivider()
                        focusColumn.frame(width: 250, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .onChange(of: fieldFocused) { _, f in vm.keepOpen = f }
        .onAppear {
            // O app nunca fica "ativo"; sem isso o painel de cores sumiria.
            let panel = NSColorPanel.shared
            panel.hidesOnDeactivate = false
            panel.showsAlpha = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        }
    }

    // MARK: Comportamento

    private var behaviorColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Comportamento")
            Toggle("Iniciar com o macOS", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Feedback háptico ao abrir", isOn: $haptics)
            Toggle("Visualizador no notch fechado", isOn: $showVisualizer)
            HStack(spacing: 6) {
                Text("Abrir após").foregroundStyle(Theme.secondary)
                Slider(value: $openDelay, in: 0...1, step: 0.05).tint(Theme.orange)
                Text(String(format: "%.2fs", openDelay)).monospacedDigit().foregroundStyle(Theme.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(size: 12))
    }

    // MARK: Tema do visualizador

    private var themeColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                sectionTitle("Tema do visualizador")
                HStack(spacing: 4) {
                    chip("Simulado", selected: !realVisualizer, accent: false) { realVisualizer = false }
                    chip("Real", icon: "waveform", selected: realVisualizer, accent: false) {
                        realVisualizer = true
                        if !CGPreflightScreenCaptureAccess() { BackdropCapture.shared.requestPermission() }
                    }
                    .help("Reage ao áudio de verdade (usa a captura de áudio: o indicador roxo fica aceso enquanto toca música)")
                }
                .padding(.leading, 8)
                Spacer()
                AudioVisualizer(isPlaying: true, color: media.accent, bars: 9,
                                barWidth: 4, spacing: 3, maxHeight: 24)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }

            HStack(spacing: 5) {
                ForEach(VisualizerStyle.allCases) { s in
                    let selected = s == style
                    Button { withAnimation(.snappy) { styleRaw = s.rawValue } } label: {
                        Text(s.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .fixedSize()
                            .foregroundStyle(selected ? Theme.orange : Color.white.opacity(0.7))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Capsule().fill(selected ? Theme.orange.opacity(0.22) : Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            HStack(spacing: 8) {
                switch style {
                case .album:
                    hint("Usa a cor predominante da capa do álbum que está tocando.")
                case .rainbow:
                    hint("Degradê com todas as cores, girando continuamente.")
                case .solid:
                    ForEach(VisualizerPresets.solids, id: \.self) { h in
                        swatch(selected: hex1 == h) { Circle().fill(Color(hex: h)) } action: { hex1 = h }
                    }
                    customPickers
                case .horizontal, .vertical:
                    ForEach(VisualizerPresets.gradients) { p in
                        swatch(selected: hex1 == p.c1 && hex2 == p.c2) {
                            Circle().fill(LinearGradient(colors: [Color(hex: p.c1), Color(hex: p.c2)],
                                                         startPoint: style == .horizontal ? .leading : .top,
                                                         endPoint: style == .horizontal ? .trailing : .bottom))
                        } action: { hex1 = p.c1; hex2 = p.c2 }
                        .help(p.name)
                    }
                    customPickers
                }
            }
            .frame(height: 26)

            sliderRow(icon: "flame.fill", value: $vizIntensity, range: 0.6...2.2,
                      label: vizIntensity < 0.9 ? "Suave" : vizIntensity < 1.3 ? "Normal" : vizIntensity < 1.8 ? "Forte" : "Insano",
                      help: "Intensidade do visualizador")
                .frame(width: 280)
        }
    }

    @ViewBuilder
    private var customPickers: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 2)
        ColorPicker("", selection: Binding(get: { Color(hex: hex1) }, set: { hex1 = $0.hexString }),
                    supportsOpacity: false)
            .labelsHidden()
            .help(style.usesTwoColors ? "Cor inicial" : "Cor personalizada")
        if style.usesTwoColors {
            Button {
                let a = hex1; hex1 = hex2; hex2 = a
            } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(PressableStyle())
            .help("Inverter cores")
            ColorPicker("", selection: Binding(get: { Color(hex: hex2) }, set: { hex2 = $0.hexString }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Cor final")
        }
    }

    private func swatch<S: View>(selected: Bool, @ViewBuilder fill: () -> S, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            fill()
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
    }

    // MARK: Sobre

    private var appearanceColumn: some View {
        let glass = appearanceRaw == IslandAppearance.glass.rawValue
        let engine = GlassEngine(rawValue: glassEngine) ?? .refraction
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Aparência").frame(height: 22)

            HStack(spacing: 5) {
                ForEach(IslandAppearance.allCases) { a in
                    chip(a.title, icon: a.icon, selected: appearanceRaw == a.rawValue, accent: true) {
                        appearanceRaw = a.rawValue
                    }
                }
            }

            if glass {
                HStack(spacing: 4) {
                    ForEach(GlassEngine.allCases) { e in
                        chip(e.title, selected: engine == e, accent: false) { glassEngine = e.rawValue }
                            .help(e == .refraction ? "Refração real (requer Gravação de Tela)" : "Vidro do sistema")
                    }
                }

                if engine == .refraction {
                    if !backdrop.permissionGranted {
                        Button("Permitir Gravação de Tela") { backdrop.requestPermission() }
                            .buttonStyle(PillButtonStyle())
                            .scaleEffect(0.9, anchor: .leading)
                            .help("Necessário para a refração. Depois de permitir, reabra o Harbor.")
                    } else {
                        sliderRow(icon: "drop.halffull", value: $glassBlur, range: 0...25,
                                  label: "\(Int(glassBlur))px", help: "Desfoque (blur)")
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(GlassVariant.allCases) { v in
                            chip(v.title, selected: glassVariant == v.rawValue, accent: false) {
                                glassVariant = v.rawValue
                            }
                        }
                    }
                }

                sliderRow(icon: "circle.lefthalf.filled", value: $glassDim, range: 0...0.85,
                          label: "\(Int(glassDim * 100))%", help: "Escurecer o vidro para melhorar a leitura")
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, icon: String? = nil, selected: Bool, accent: Bool,
                      action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: accent ? 11.5 : 10.5, weight: .semibold))
            .foregroundStyle(selected ? (accent ? Theme.orange : .white) : Color.white.opacity(0.6))
            .padding(.horizontal, accent ? 9 : 8)
            .frame(height: accent ? 24 : 21)
            .background(Capsule().fill(selected ? (accent ? Theme.orange.opacity(0.22) : Color.white.opacity(0.2))
                                                : Color.white.opacity(0.07)))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PressableStyle())
    }

    private func sliderRow(icon: String, value: Binding<Double>, range: ClosedRange<Double>,
                           label: String, help: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Theme.secondary)
            Slider(value: value, in: range).tint(Theme.orange).controlSize(.mini)
            Text(label).monospacedDigit().foregroundStyle(Theme.secondary).frame(minWidth: 30, alignment: .trailing).fixedSize()
        }
        .font(.system(size: 10.5))
        .help(help)
    }

    // MARK: Barra lateral

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { sec in
                let selected = section == sec
                Button { withAnimation(.snappy) { sectionRaw = sec.rawValue } } label: {
                    Label(sec.title, systemImage: sec.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Theme.orange : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Theme.orange.opacity(0.2) : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Sobre

    private var aboutSection: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 52, height: 52)
                Text("Harbor").font(.system(size: 14, weight: .bold))
                Text("v\(HarborLinks.version) (\(HarborLinks.build))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                Button("Sair") { NSApp.terminate(nil) }.buttonStyle(PillButtonStyle(tint: .red)).scaleEffect(0.8)
            }
            .frame(width: 118)
            ModuleDivider()
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Links")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    linkCard("Repositório oficial", "Código, releases e documentação", "chevron.left.forwardslash.chevron.right", HarborLinks.repo)
                    linkCard("Enviar feedback", "Ideias, sugestões e elogios", "bubble.left.and.text.bubble.right.fill", HarborLinks.feedback)
                    linkCard("Reportar um problema", "Já vai com a versão do app e do macOS", "ladybug.fill", HarborLinks.bugWithContext)
                    linkCard("Manual (PDF)", "Passo a passo das configurações", "book.fill", HarborLinks.manual)
                }
            }
        }
    }

    private func linkCard(_ title: String, _ sub: String, _ icon: String, _ url: URL) -> some View {
        Button { HarborLinks.open(url) } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.orange)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.orange.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(sub).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(url.absoluteString)
    }

    // MARK: Geral › Telas

    private var screenColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Telas")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ScreenMode.allCases) { m in
                    chip(m.title, selected: screenMode == m.rawValue, accent: false) { screenMode = m.rawValue }
                }
            }
            Toggle("Ocultar em tela cheia", isOn: $hideInFullscreen)
            Toggle("Brilho vivo com música", isOn: $liveGlow)
        }
        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
        .onChange(of: screenMode) { _, _ in
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
    }

    // MARK: Geral › Avisos

    private var alertsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Avisos no notch")
            Toggle("Volume", isOn: $alertVolume)
            Toggle("Brilho", isOn: $alertBrightness)
            Toggle("Bateria e carregador", isOn: $alertPower)
            Toggle("Fones Bluetooth", isOn: $alertBluetooth)
        }
        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
    }

    // MARK: Geral › Atalhos

    private var shortcutsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Atalhos")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                shortcutRow("Abrir", HotKeys.toggle.label)
                shortcutRow("Cópias", HotKeys.clipboard.label)
                shortcutRow("Nota", HotKeys.note.label)
                shortcutRow("Conta-gotas", HotKeys.picker.label)
                shortcutRow("Fixar app", HotKeys.pinApp.label)
                shortcutRow("Mudo mic", HotKeys.mic.label)
                shortcutRow("Fechar", "Esc")
            }
        }
    }

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 4)
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
        }
    }

    // MARK: Integrações › Claude Code

    private var claudeColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "asterisk").font(.system(size: 12, weight: .black))
                    .foregroundStyle(ClaudeActivity.claudeColor)
                sectionTitle("Claude Code no notch")
                if claude.hooksInstalled {
                    Label("Ativo", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green)
                }
            }
            Text(claude.hooksInstalled
                 ? "O notch mostra quando o Claude está trabalhando, quando termina e quando pede permissão. Vale para sessões novas do Claude Code."
                 : "Adiciona hooks em ~/.claude/settings.json (é feito um backup antes) para o notch mostrar quando o Claude está trabalhando, termina ou pede permissão.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if claude.hooksInstalled {
                    Button("Remover hooks") { run { try claude.uninstallHooks() } }
                        .buttonStyle(PillButtonStyle(tint: .white))
                } else {
                    Button("Instalar hooks") { run { try claude.installHooks() } }
                        .buttonStyle(PillButtonStyle(tint: ClaudeActivity.claudeColor))
                }
                if let s = claude.workingSession {
                    Label("\(s.project) trabalhando", systemImage: "circle.fill")
                        .font(.system(size: 11)).foregroundStyle(ClaudeActivity.claudeColor)
                }
            }
            if !claudeError.isEmpty {
                Text(claudeError).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
            }
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); claudeError = "" } catch { claudeError = error.localizedDescription }
    }

    // MARK: Apps fixados

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionTitle("Apps fixados")
                Text("Quando você sai deles, viram uma bolha à direita do notch — clique para voltar.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    let candidates = pins.runningCandidates
                    if candidates.isEmpty { Text("Nenhum app aberto disponível") }
                    ForEach(candidates) { app in
                        Button {
                            withAnimation(.snappy) { pins.pin(app.bundleID) }
                        } label: {
                            Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                        }
                    }
                } label: {
                    Label("Fixar app aberto", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(Theme.orange.opacity(0.2)))
                .foregroundStyle(Theme.orange)
            }

            if pins.pinnedInfo.isEmpty {
                HStack(spacing: 6) {
                    Text("Nenhum app fixado. Use o botão acima ou aperte").foregroundStyle(Theme.secondary)
                    Text(HotKeys.pinApp.label)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
                    Text("com o app na frente.").foregroundStyle(Theme.secondary)
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pins.pinnedInfo) { app in
                            VStack(spacing: 5) {
                                Image(nsImage: app.icon).resizable().frame(width: 40, height: 40)
                                Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 78)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                            .overlay(alignment: .topTrailing) {
                                Button { withAnimation(.snappy) { pins.unpin(app.bundleID) } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                                        .foregroundStyle(.white, Color.gray.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                                .help("Desafixar")
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Integrações › Aviso nativo do macOS

    private var hudColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Aviso do macOS")
            Toggle("Substituir pelo do Harbor", isOn: $replaceHUD)
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                .onChange(of: replaceHUD) { _, _ in keys.refresh() }
            Text("Volume e brilho aparecem só no notch, sem o aviso nativo.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if replaceHUD {
                if keys.active {
                    Label("Ativo", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green)
                } else if !keys.trusted {
                    Button("Permitir Acessibilidade") { keys.requestAccessibility() }
                        .buttonStyle(PillButtonStyle())
                        .scaleEffect(0.9, anchor: .leading)
                }
            }
        }
    }

    // MARK: Integrações › Foco do macOS

    private var focusColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Timer de foco → Modo Foco")
            Text("Nomes de Atalhos (app Atalhos) para rodar ao iniciar e ao terminar o foco — ex.: um que liga “Não Perturbe”.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            shortcutField("Ao iniciar", text: $focusOn, placeholder: "Ativar Foco")
            shortcutField("Ao terminar", text: $focusOff, placeholder: "Desativar Foco")
        }
    }

    private func shortcutField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).frame(width: 74, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($fieldFocused)
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                .onSubmit { fieldFocused = false }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
    }
}
