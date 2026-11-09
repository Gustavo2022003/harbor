import SwiftUI

/// Notch fechado: só o preto do notch, com "asas" quando há música ou timer.
struct ClosedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var alerts: AlertCenter
    @EnvironmentObject var claude: ClaudeActivity
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var downloads: DownloadsMonitor
    @EnvironmentObject var bluetooth: BluetoothMonitor
    @AppStorage(Prefs.showVisualizer) private var showVisualizer = true

    var body: some View {
        let wing = vm.activityWing
        let h = vm.notchSize.height

        HStack(spacing: 0) {
            switch vm.closedActivity {
            case .music:
                HStack(spacing: 5) {
                    ArtworkView(image: media.artwork, size: h - 10, radius: 6)
                    // Claude trabalhando por trás da música: quadrado do tamanho da capa, ao lado dela
                    if vm.claudeBehindMusic {
                        ClaudeTile(size: h - 10)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                            .help("Claude trabalhando — passe o mouse para ver na aba Agora")
                    }
                }
                .frame(width: wing, alignment: .center)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if vm.musicOnBluetooth {
                        Image(systemName: bluetooth.primaryAudio?.icon ?? "headphones")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .transition(.scale.combined(with: .opacity))
                            .help("Som saindo em \(bluetooth.outputName)")
                    }
                    if showVisualizer {
                        AudioVisualizer(isPlaying: media.isPlaying, color: media.accent,
                                        bars: 5, barWidth: 3, spacing: 2, maxHeight: min(22, h - 8))
                    } else {
                        Image(systemName: "waveform").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(media.accent)
                    }
                }
                .frame(width: wing, alignment: .center)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: vm.musicOnBluetooth)
            case .timer:
                Image(systemName: timer.mode == .focus ? "timer" : "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: wing, alignment: .center)
                Spacer(minLength: 0)
                Text(timer.formatted)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.orange)
                    .opacity(timer.isRunning ? 1 : 0.55)
                    .fixedSize()
                    .frame(width: wing, alignment: .center)
            case .alert:
                if let a = alerts.current {
                    Image(systemName: a.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(a.tint)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: wing, alignment: .center)
                        .id("alert-icon")
                    Spacer(minLength: 0)
                    Group {
                        if let level = a.level {
                            LevelBar(level: level, tint: a.tint).frame(width: wing - 28, height: 6)
                        } else {
                            Text(a.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.trailing, 6)
                        }
                    }
                    .frame(width: wing, alignment: .center)
                } else {
                    Spacer(minLength: 0)
                }
            case .claude:
                ClaudeSpinner().frame(width: wing, alignment: .center)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ClaudeActivity.duration(ctx.date.timeIntervalSince(claude.workingSession?.since ?? ctx.date)))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ClaudeActivity.claudeColor)
                        .fixedSize()
                }
                .frame(width: wing, alignment: .center)
            case .meeting:
                let m = calendar.nextMeeting
                Image(systemName: "video.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m?.color ?? Theme.orange)
                    .frame(width: wing, alignment: .center)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    Text(Self.meetingCountdown(m?.start, now: ctx.date))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(m?.color ?? Theme.orange)
                        .fixedSize()
                }
                .frame(width: wing, alignment: .center)
            case .download:
                let d = downloads.active
                DownloadRing(fraction: d?.fraction)
                    .frame(width: 18, height: 18)
                    .frame(width: wing, alignment: .center)
                Spacer(minLength: 0)
                Group {
                    if let f = d?.fraction {
                        Text("\(Int(f * 100))%")
                    } else {
                        Text(DownloadsMonitor.format(bytes: d?.bytes ?? 0))
                    }
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.4, green: 0.75, blue: 1))
                .contentTransition(.numericText())
                .fixedSize()
                .frame(width: wing, alignment: .center)
                .help(d.map { "\($0.name) · \(DownloadsMonitor.format(bytes: Int64($0.speed)))/s" } ?? "")
            case .none:
                Spacer(minLength: 0)
            }
        }
        .frame(height: h)
        .transition(.opacity)
    }

    static func meetingCountdown(_ start: Date?, now: Date) -> String {
        guard let start else { return "" }
        let mins = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return mins <= 0 ? "agora" : "em \(mins) min"
    }
}

/// Barra de nível (volume/brilho) do aviso.
struct LevelBar: View {
    var level: Double
    var tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(6, g.size.width * min(1, max(0, level))))
            }
        }
        .animation(.snappy(duration: 0.18), value: level)
    }
}

/// "Asterisco" do Claude girando enquanto ele trabalha.
struct ClaudeSpinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Image(systemName: "asterisk")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(ClaudeActivity.claudeColor)
                .rotationEffect(.degrees(t * 120))
                .scaleEffect(1 + 0.12 * sin(t * 4))
        }
    }
}

/// Selo do Claude (asterisco girando num círculo preto com contorno) no tamanho da capa, ao lado dela.
struct ClaudeTile: View {
    var size: CGFloat
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Image(systemName: "asterisk")
                .font(.system(size: size * 0.5, weight: .black))
                .foregroundStyle(ClaudeActivity.claudeColor)
                .rotationEffect(.degrees(t * 120))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black))
                .overlay(Circle().strokeBorder(ClaudeActivity.claudeColor.opacity(0.6), lineWidth: 1.5))
        }
    }
}

/// Brilho suave em volta do island fechado, pulsando com a música.
struct LiveGlow: View {
    var color: Color
    @ObservedObject private var audio = AudioLevels.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let bass = audio.isRunning ? Double(audio.bands.prefix(3).max() ?? 0)
                : (sin(ctx.date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2 * 0.6
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color)
                .blur(radius: 10)
                .opacity(0.25 + bass * 0.45)
                .scaleEffect(x: 1 + bass * 0.04, y: 1 + bass * 0.12, anchor: .top)
        }
    }
}

// MARK: - Componentes reutilizáveis

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}


struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double = 100
    var minValue: Double = 0

    var body: some View {
        GeometryReader { g in
            let pts = points(in: g.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let range = max(maxValue - minValue, 0.0001)
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { i, v in
            let n = min(max((v - minValue) / range, 0), 1)
            return CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(n) * (size.height - 2) - 1)
        }
    }
}

struct CircleIconButton: View {
    var systemName: String
    var tint: Color = .white
    var background: Color = Color.white.opacity(0.1)
    var size: CGFloat = 34
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ModuleDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 8)
    }
}

// MARK: - Bolha do odômetro

struct OdometerBubble: View {
    @EnvironmentObject var odo: MouseOdometer
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        let text = odo.format(odo.todayMeters)
        HStack(spacing: 5) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.orange)
            Text(text)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: text)
        }
        .padding(.horizontal, 10)
        .frame(height: max(18, vm.notchSize.height - 6))
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
        .fixedSize()
        .background(GeometryReader { g in
            Color.clear
                .onAppear { vm.bubbleWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in vm.bubbleWidth = w }
        })
    }
}

// MARK: - Bolhas de apps fixados (à esquerda)

struct PinnedAppBubbles: View {
    @EnvironmentObject var pins: AppPinStore
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var mic: MicController

    var body: some View {
        let h = max(18, vm.notchSize.height - 6)
        HStack(spacing: 5) {
            if mic.isMuted || mic.inUse {
                MicBubble(height: h).transition(.scale(scale: 0.3).combined(with: .opacity))
            }
            ForEach(pins.visible) { app in
                PinnedAppBubble(app: app, height: h)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .fixedSize()
        .background(GeometryReader { g in
            Color.clear
                .onAppear { vm.leftBubblesWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in vm.leftBubblesWidth = w }
        })
        .onDisappear { vm.leftBubblesWidth = 0 }
    }
}

struct PinnedAppBubble: View {
    @EnvironmentObject var pins: AppPinStore
    let app: AppPinStore.PinnedApp
    let height: CGFloat
    @Local private var hover = false

    var body: some View {
        Button { pins.activate(app.bundleID) } label: {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: height - 4, height: height - 4)
                .frame(width: height + 6, height: height)
                .background(Capsule().fill(Color.black))
                .overlay(Capsule().strokeBorder(Color.white.opacity(hover ? 0.25 : 0.07)))
                .overlay(alignment: .topTrailing) {
                    if let badge = pins.badges[app.bundleID] {
                        Text(badge.count > 3 ? "99+" : badge)
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Capsule().fill(Color.red))
                            .overlay(Capsule().strokeBorder(Color.black, lineWidth: 1.5))
                            .offset(x: 4, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: pins.badges[app.bundleID])
                .scaleEffect(hover ? 1.12 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { hover = h } }
        .help("Ir para \(app.name)" + (pins.badges[app.bundleID].map { " · \($0) não lidas" } ?? ""))
        .contextMenu {
            Button("Ir para \(app.name)") { pins.activate(app.bundleID) }
            Button("Desafixar \(app.name)") { withAnimation { pins.unpin(app.bundleID) } }
        }
    }
}

/// Bolha do microfone: laranja quando em uso, vermelha quando no mudo. Clique alterna o mudo.
struct MicBubble: View {
    @EnvironmentObject var mic: MicController
    let height: CGFloat
    @Local private var hover = false

    var body: some View {
        let tint: Color = mic.isMuted ? .red : Theme.orange
        Button { mic.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if mic.isMuted {
                    Text("Mudo").font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: height)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().strokeBorder(tint.opacity(hover ? 0.8 : 0.45)))
            .scaleEffect(hover ? 1.08 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { hover = h } }
        .help(mic.isMuted ? "Microfone mudo — clique para ativar (⌥M)" : "Microfone em uso — clique para mutar (⌥M)")
    }
}

/// Anel de progresso do download (gira quando o total é desconhecido).
struct DownloadRing: View {
    var fraction: Double?
    private let tint = Color(red: 0.4, green: 0.75, blue: 1)

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
            if let fraction {
                Circle().trim(from: 0, to: max(0.03, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate * 360))
                }
            }
            Image(systemName: "arrow.down").font(.system(size: 8, weight: .heavy)).foregroundStyle(tint)
        }
    }
}
