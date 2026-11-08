import SwiftUI

/// Aba "Copiados": histórico do ⌘C. Clique num card para colar.
struct ClipboardTabView: View {
    @EnvironmentObject var clips: ClipboardStore
    @EnvironmentObject var vm: NotchViewModel
    @Local private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return clips.sortedItems }
        return clips.sortedItems.filter { item in
            switch item.kind {
            case .text: return (item.text ?? "").lowercased().contains(q)
            case .files: return (item.paths ?? []).contains { $0.lowercased().contains(q) }
            case .image: return "imagem image png".contains(q)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if clips.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24)).foregroundStyle(Theme.orange)
                    Text("Nada copiado ainda").font(.system(size: 13, weight: .semibold))
                    Text("Copie algo com ⌘C e ele aparece aqui. Clique para colar.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if filtered.isEmpty {
                    Text("Nada encontrado para “\(query)”")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(filtered) { item in
                                ClipCard(item: item)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.95),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                }
            }
        }
        .padding(.horizontal, 6)
        .onChange(of: vm.focusRequest) { _, req in
            guard req == .clipboardSearch else { return }
            searchFocused = true
            vm.focusRequest = nil
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
            TextField("Buscar…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { query = ""; searchFocused = false }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(width: 210, height: 26)
        .background(Capsule().fill(Color.white.opacity(searchFocused ? 0.14 : 0.08)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Área de transferência").font(.system(size: 13, weight: .bold))
            Text("\(clips.items.count)")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange)
            searchField.padding(.leading, 6)
            Spacer()
            if !clips.accessibilityTrusted {
                HStack(spacing: 6) {
                    Text("Clicar só copia (use ⌘V).")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Button("Ativar colar automático") { clips.requestAccessibility() }
                        .buttonStyle(PillButtonStyle())
                        .help("Requer permissão de Acessibilidade para simular ⌘V")
                }
            }
            if clips.items.contains(where: { !$0.pinned }) {
                Button { withAnimation(.snappy) { clips.clearUnpinned() } } label: {
                    Label("Limpar", systemImage: "trash")
                }
                .buttonStyle(PillButtonStyle(tint: .white))
                .help("Remove tudo, exceto os itens fixados")
            }
        }
        .frame(height: 28)
    }
}

struct ClipCard: View {
    @EnvironmentObject var clips: ClipboardStore
    let item: ClipItem
    @Local private var hover = false
    @Local private var copiedFlash = false

    var body: some View {
        Button {
            let pasted = clips.paste(item)
            if !pasted {
                withAnimation(.snappy) { copiedFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    withAnimation(.snappy) { copiedFlash = false }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if let icon = appIcon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if item.pinned && !hover {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.orange)
                    }
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(9)
            .frame(width: 176, height: 100)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hover ? Color.white.opacity(0.12) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(item.pinned ? Theme.orange.opacity(0.5) : Theme.stroke))
            .overlay {
                if copiedFlash {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                        .overlay(Label("Copiado · ⌘V", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.green))
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .topTrailing) {
            if hover {
                HStack(spacing: 4) {
                    smallButton(item.pinned ? "pin.slash.fill" : "pin.fill",
                                tint: Theme.orange) { withAnimation(.snappy) { clips.togglePin(item) } }
                    smallButton("xmark", tint: .white) { withAnimation(.snappy) { clips.remove(item) } }
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(item.kind == .text ? String((item.text ?? "").prefix(400)) : "")
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text((item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        case .image:
            if let img = clips.image(for: item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Label("Imagem", systemImage: "photo").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        case .files:
            let paths = item.paths ?? []
            HStack(spacing: 8) {
                if let first = paths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                        .resizable().frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "")
                        .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if paths.count > 1 {
                        Text("+\(paths.count - 1) arquivo\(paths.count > 2 ? "s" : "")")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    private var appIcon: NSImage? {
        guard let id = item.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func smallButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(0.75)))
        }
        .buttonStyle(PressableStyle())
    }
}
