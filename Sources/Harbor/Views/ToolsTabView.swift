import SwiftUI

/// Aba "Ferramentas": nota rápida, conta-gotas e monitor de rede.
struct ToolsTabView: View {
    var body: some View {
        HStack(spacing: 14) {
            QuickNoteModule().frame(maxWidth: .infinity)
            ModuleDivider()
            ColorPickerModule().frame(width: 230)
            ModuleDivider()
            NetworkModule().frame(width: 230)
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
