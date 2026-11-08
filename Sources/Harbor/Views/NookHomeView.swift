import SwiftUI

/// Aba principal: Mídia | CPU + Bateria | Timer | Tarefas
struct NookHomeView: View {
    var body: some View {
        HStack(spacing: 14) {
            MediaModule().frame(width: 250)
            ModuleDivider()
            StatsModule().frame(width: 176)
            ModuleDivider()
            TimerModule().frame(width: 256)
            ModuleDivider()
            TasksModule().frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Mídia

struct MediaModule: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: media.artwork, size: 104, radius: 16)
                .shadow(color: media.accent.opacity(media.artwork == nil ? 0 : 0.25), radius: 12)
                .onTapGesture { media.openSourceApp() }

            VStack(spacing: 4) {
                if let info = media.info {
                    MarqueeText(text: info.title, font: .system(size: 15, weight: .semibold))
                    Text(info.artist.isEmpty ? info.album : info.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                } else {
                    Text("Nada tocando").font(.system(size: 15, weight: .semibold))
                    Text("Abra o Spotify ou o Música")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                }

                MediaControls(size: 1.0)
                    .padding(.top, 14)
                    .disabled(media.info == nil)
                    .opacity(media.info == nil ? 0.4 : 1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct MediaControls: View {
    @EnvironmentObject var media: MediaController
    var size: CGFloat

    var body: some View {
        HStack(spacing: 26 * size) {
            Button { media.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 19 * size))
            }
            Button { media.togglePlayPause() } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 27 * size))
                    .frame(width: 30 * size)
                    .contentTransition(.symbolEffect(.replace))
            }
            Button { media.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 19 * size))
            }
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
    }
}

/// Texto que rola horizontalmente quando não cabe.
struct MarqueeText: View {
    var text: String
    var font: Font
    @Local private var textWidth: CGFloat = 0
    @Local private var animate = false

    var body: some View {
        GeometryReader { g in
            let overflow = textWidth > g.size.width
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(GeometryReader { t in
                    Color.clear.onAppear { textWidth = t.size.width }
                        .onChange(of: text) { textWidth = t.size.width }
                })
                .offset(x: overflow && animate ? -(textWidth - g.size.width) : 0)
                .frame(width: g.size.width, alignment: overflow ? .leading : .center)
                .animation(overflow ? .linear(duration: Double(textWidth - g.size.width) / 25)
                    .delay(1.5).repeatForever(autoreverses: true) : .default, value: animate)
                .onAppear { animate = true }
                .onChange(of: text) { animate = false; DispatchQueue.main.async { animate = true } }
        }
        .frame(height: 20)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                     .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: - CPU / Bateria

struct StatsModule: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        HStack(spacing: 10) {
            StatCard(icon: "cpu", value: system.cpu, color: Theme.green,
                     history: system.cpuHistory, minValue: 0, maxValue: 100)
            if system.hasBattery {
                StatCard(icon: system.isCharging ? "battery.100percent.bolt" : batteryIcon,
                         value: system.battery, color: Theme.yellow,
                         history: system.batteryHistory,
                         minValue: max(0, (system.batteryHistory.min() ?? 0) - 10),
                         maxValue: min(100, (system.batteryHistory.max() ?? 100) + 5))
            }
        }
    }

    private var batteryIcon: String {
        switch system.battery {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

struct StatCard: View {
    var icon: String
    var value: Double
    var color: Color
    var history: [Double]
    var minValue: Double
    var maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 0)
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(value.rounded()))
            }
            Spacer(minLength: 0)
            Sparkline(values: history, color: color, maxValue: maxValue, minValue: minValue)
                .frame(height: 52)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
    }
}

// MARK: - Timer

struct TimerModule: View {
    @EnvironmentObject var timer: FocusTimer

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                modeButton("Foco", .focus)
                modeButton("Pausa", .pause)
                Spacer(minLength: 0)
                Text(timer.formatted)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.orange)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: timer.formatted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            RulerPicker(value: Binding(get: { timer.selectedMinutes }, set: { timer.setMinutes($0) }),
                        range: 1...90)
                .frame(height: 42)
                .opacity(timer.isRunning || timer.hasProgress ? 0.35 : 1)
                .allowsHitTesting(!timer.isRunning && !timer.hasProgress)

            HStack(spacing: 8) {
                Button { timer.toggle() } label: {
                    Text(primaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.orange.opacity(0.2)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())

                CircleIconButton(systemName: timer.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                 tint: Theme.orange, background: Theme.orange.opacity(0.2)) {
                    timer.soundEnabled.toggle()
                }
                CircleIconButton(systemName: "arrow.counterclockwise") { timer.reset() }
                    .opacity(timer.hasProgress ? 1 : 0.5)
                Spacer(minLength: 0)
            }
        }
    }

    private var primaryTitle: String {
        if timer.isRunning { return "Pausar" }
        return timer.hasProgress ? "Continuar" : "Iniciar timer"
    }

    private func modeButton(_ title: String, _ mode: FocusTimer.Mode) -> some View {
        let selected = timer.mode == mode
        return Button { withAnimation(.snappy) { timer.setMode(mode) } } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(selected ? Theme.orange : Color.white.opacity(0.7))
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(Capsule().fill(selected ? Theme.orange.opacity(0.22) : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Régua deslizante para escolher minutos.
struct RulerPicker: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    private let spacing: CGFloat = 9
    @Local private var dragStart: Int?

    var body: some View {
        GeometryReader { g in
            let mid = g.size.width / 2
            ZStack(alignment: .topLeading) {
                ForEach(Array(range), id: \.self) { m in
                    let x = mid + CGFloat(m - value) * spacing
                    if x > -20 && x < g.size.width + 20 {
                        VStack(spacing: 3) {
                            Text(m % 5 == 0 ? "\(m)" : "")
                                .font(.system(size: 11, weight: m == value ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(m == value ? Color.white : Theme.orange.opacity(0.75))
                                .frame(width: 24, height: 13)
                            Rectangle()
                                .fill(m == value ? Color.white : Color.white.opacity(m % 5 == 0 ? 0.55 : 0.3))
                                .frame(width: m == value ? 2 : 1.3, height: m % 5 == 0 ? 16 : 12)
                                .frame(height: 16, alignment: .bottom)
                        }
                        .position(x: x, y: 16)
                    }
                }
                Triangle()
                    .fill(Theme.orange)
                    .frame(width: 9, height: 6)
                    .position(x: mid, y: g.size.height - 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if dragStart == nil { dragStart = value }
                        let delta = Int((-gesture.translation.width / spacing).rounded())
                        let nv = min(max(dragStart! + delta, range.lowerBound), range.upperBound)
                        if nv != value {
                            value = nv
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onScrollWheel { dx, dy in
                let d = abs(dx) > abs(dy) ? -dx : dy
                guard abs(d) > 0.5 else { return }
                let nv = min(max(value + (d > 0 ? 1 : -1), range.lowerBound), range.upperBound)
                if nv != value { value = nv }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Tarefas

struct TasksModule: View {
    @EnvironmentObject var tasks: TaskStore
    @EnvironmentObject var vm: NotchViewModel
    @Local private var adding = false
    @Local private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if tasks.items.isEmpty && !adding {
                Spacer(minLength: 0)
                Image(systemName: "checklist")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Theme.orange)
                Text("Nenhuma tarefa ainda")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                addButton
                Spacer(minLength: 0)
            } else {
                HStack {
                    Text("Tarefas").font(.system(size: 13, weight: .bold))
                    Text("\(tasks.items.filter { !$0.done }.count)")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange)
                    Spacer()
                    if tasks.items.contains(where: { $0.done }) {
                        Button("Limpar") { withAnimation { tasks.clearDone() } }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    Button { startAdding() } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.orange)
                    }
                    .buttonStyle(PressableStyle())
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(tasks.items) { item in
                            TaskRow(item: item)
                        }
                        if adding { inputField }
                    }
                }
            }
            if adding && tasks.items.isEmpty { inputField }
        }
        .onChange(of: focused) { _, f in
            vm.keepOpen = f
            if !f { adding = false; draft = "" }
        }
    }

    private var addButton: some View {
        Button { startAdding() } label: {
            Label("Adicionar tarefa", systemImage: "plus")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.orange)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Theme.orange.opacity(0.2)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private var inputField: some View {
        TextField("Nova tarefa…", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .focused($focused)
            .onSubmit {
                tasks.add(draft)
                draft = ""
                focused = true
            }
            .onExitCommand { focused = false }
    }

    private func startAdding() {
        adding = true
        vm.makeKey?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }
}

struct TaskRow: View {
    @EnvironmentObject var tasks: TaskStore
    let item: TaskItem
    @Local private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.snappy) { tasks.toggle(item) } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? Theme.orange : Color.white.opacity(0.5))
            }
            .buttonStyle(PressableStyle())
            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Theme.secondary : .white)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hover {
                Button { withAnimation { tasks.remove(item) } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hover = $0 }
    }
}

// MARK: - Scroll wheel

extension View {
    func onScrollWheel(_ handler: @escaping (CGFloat, CGFloat) -> Void) -> some View {
        overlay(ScrollWheelCatcher(handler: handler))
    }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    let handler: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.handler = handler
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.handler = handler }

    final class CatcherView: NSView {
        var handler: ((CGFloat, CGFloat) -> Void)?
        private var accum: CGFloat = 0

        override func scrollWheel(with e: NSEvent) {
            let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : e.scrollingDeltaY
            accum += d
            let threshold: CGFloat = e.hasPreciseScrollingDeltas ? 8 : 1
            while abs(accum) >= threshold {
                handler?(0, accum > 0 ? 1 : -1)
                accum -= accum > 0 ? threshold : -threshold
            }
        }

        // Deixa cliques/arrastos passarem para o SwiftUI
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, e.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }
    }
}
