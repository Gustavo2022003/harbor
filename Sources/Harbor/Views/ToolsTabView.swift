import SwiftUI

/// Aba "Ferramentas": nota rápida, conta-gotas, monitor de rede e aparelhos Bluetooth.
struct ToolsTabView: View {
    var body: some View {
        HStack(spacing: 14) {
            QuickNoteModule().frame(maxWidth: .infinity)
            ModuleDivider()
            ColorPickerModule().frame(width: 200)
            ModuleDivider()
            NetworkModule().frame(width: 200)
            ModuleDivider()
            BluetoothModule().frame(width: 240)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Nota rápida

struct QuickNoteModule: View {
    @EnvironmentObject var vm: NotchViewModel
    @AppStorage("quickNote") private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Nota rápida", systemImage: "note.text")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                Spacer()
                Text(HotKeys.note.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
                if !note.isEmpty {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note, forType: .string) }
                        label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("Copiar nota")
                    Button { note = "" } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("Apagar nota")
                }
            }
            .font(.system(size: 11))
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Escreva algo… fica salvo aqui.")
                        .font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.3))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.1 : 0.06)))
        }
        .onChange(of: focused) { _, f in
            vm.keepOpen = f
            if f { vm.makeKey?() }
        }
        .onChange(of: vm.focusRequest) { _, req in
            guard req == .note else { return }
            focused = true
            vm.focusRequest = nil
        }
        .onExitCommand { focused = false }
    }
}

// MARK: - Conta-gotas

struct ColorPickerModule: View {
    @EnvironmentObject var picker: ColorPickerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Conta-gotas", systemImage: "eyedropper.halffull")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                Spacer()
                Text(HotKeys.picker.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            Button { picker.pick() } label: {
                Label("Capturar cor da tela", systemImage: "eyedropper.full")
            }
            .buttonStyle(PillButtonStyle())

            if picker.recent.isEmpty {
                Text("A cor vai para a área de transferência em HEX.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 6), spacing: 6) {
                    ForEach(picker.recent, id: \.self) { hex in
                        Button { picker.copy(hex) } label: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(PressableStyle())
                        .help("\(hex) — clique para copiar")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Rede

struct NetworkModule: View {
    @EnvironmentObject var system: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rede", systemImage: "network")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
            HStack(spacing: 10) {
                rate("arrow.down", SystemMonitor.formatRate(system.netDown), Color(red: 0.4, green: 0.75, blue: 1))
                rate("arrow.up", SystemMonitor.formatRate(system.netUp), Theme.green)
            }
            ZStack {
                Sparkline(values: system.netDownHistory, color: Color(red: 0.4, green: 0.75, blue: 1),
                          maxValue: max(1, (system.netDownHistory + system.netUpHistory).max() ?? 1))
                Sparkline(values: system.netUpHistory, color: Theme.green,
                          maxValue: max(1, (system.netDownHistory + system.netUpHistory).max() ?? 1))
                    .opacity(0.8)
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        }
    }

    private func rate(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Aparelhos Bluetooth

struct BluetoothModule: View {
    @EnvironmentObject var bt: BluetoothMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(BluetoothMonitor.tint)
                Spacer()
                if bt.outputIsBluetooth {
                    Label("Som aqui", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .help("Som saindo em \(bt.outputName)")
                }
            }
            if bt.devices.isEmpty {
                Spacer(minLength: 0)
                Text("Nenhum aparelho conectado")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(bt.devices) { row($0) }
                    }
                }
            }
        }
        .onAppear { bt.refresh() }
    }

    private func row(_ d: BluetoothMonitor.Device) -> some View {
        let playing = bt.outputIsBluetooth && bt.outputName.hasPrefix(d.shortName)
        return HStack(spacing: 8) {
            Image(systemName: d.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(playing ? BluetoothMonitor.tint : .white)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.shortName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 7) {
                    if d.left != nil || d.right != nil {
                        part("E", d.left); part("D", d.right)
                        if d.caseLevel != nil { part("Estojo", d.caseLevel) }
                    } else if let m = d.main {
                        part(nil, m)
                    } else {
                        Text("Bateria indisponível").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
    }

    @ViewBuilder
    private func part(_ label: String?, _ value: Int?) -> some View {
        if let value {
            HStack(spacing: 3) {
                if let label { Text(label).foregroundStyle(Theme.secondary) }
                BatteryGlyph(level: value)
                Text("\(value)%").monospacedDigit().foregroundStyle(value <= 20 ? .red : .white.opacity(0.85))
            }
            .font(.system(size: 10, weight: .semibold))
        }
    }
}

/// Pilha pequena desenhada (preenchimento proporcional; vermelha abaixo de 20%).
struct BatteryGlyph: View {
    var level: Int
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(level <= 20 ? Color.red : Theme.green)
                    .frame(width: max(1.5, 13 * CGFloat(min(100, max(0, level))) / 100))
                    .padding(1.5)
            }
            .frame(width: 17, height: 9)
            RoundedRectangle(cornerRadius: 0.5).fill(Color.white.opacity(0.5)).frame(width: 1.5, height: 4)
        }
    }
}
