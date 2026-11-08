import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Mídia (player completo)

struct MediaTabView: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        HStack(spacing: 22) {
            ArtworkView(image: media.artwork, size: 124, radius: 18)
                .shadow(color: media.accent.opacity(0.35), radius: 18)
                .onTapGesture { media.openSourceApp() }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.info?.title ?? "Nada tocando")
                            .font(.system(size: 18, weight: .bold)).lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let src = media.info?.source {
                        Text(src.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9).frame(height: 22)
                            .background(Capsule().fill(media.accent.opacity(0.18)))
                            .foregroundStyle(media.accent)
                    }
                    AudioVisualizer(isPlaying: media.isPlaying, color: media.accent, bars: 5)
                        .padding(.leading, 6)
                }

                ProgressScrubber()
                    .padding(.top, 6)

                HStack {
                    Spacer()
                    MediaControls(size: 1.15)
                    Spacer()
                }
                .padding(.top, 2)
                .disabled(media.info == nil)
                .opacity(media.info == nil ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 16)
    }

    private var subtitle: String {
        guard let i = media.info else { return "Toque algo no Spotify ou no Música" }
        return [i.artist, i.album].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}

struct ProgressScrubber: View {
    @EnvironmentObject var media: MediaController
    @Local private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = media.info?.duration ?? 0
            let current = dragValue ?? media.info?.currentPosition(at: ctx.date) ?? 0
            let fraction = duration > 0 ? current / duration : 0

            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(media.accent)
                            .frame(width: max(0, g.size.width * fraction))
                    }
                    .frame(height: dragValue == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                guard duration > 0 else { return }
                                dragValue = min(max(0, v.location.x / g.size.width), 1) * duration
                            }
                            .onEnded { _ in
                                if let d = dragValue { media.seek(to: d) }
                                dragValue = nil
                            }
                    )
                    .animation(.snappy(duration: 0.2), value: dragValue == nil)
                }
                .frame(height: 12)

                HStack {
                    Text(Self.time(current))
                    Spacer()
                    Text("-" + Self.time(max(0, duration - current)))
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
            }
        }
    }

    static func time(_ t: Double) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Agenda

struct CalendarTabView: View {
    @EnvironmentObject var cal: CalendarStore

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(cal.selectedDate.formatted(.dateTime.weekday(.wide)).capitalized)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.orange)
                Text(cal.selectedDate.formatted(.dateTime.day().month(.wide)))
                    .font(.system(size: 22, weight: .bold))
                weekStrip
            }
            .frame(width: 330, alignment: .leading)

            ModuleDivider()

            Group {
                if !cal.authorized {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 24)).foregroundStyle(Theme.orange)
                        Text(cal.denied ? "Acesso ao calendário negado. Ative em Ajustes do Sistema › Privacidade › Calendários."
                                        : "Permita o acesso para ver seus eventos aqui.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                        if !cal.denied {
                            Button("Permitir acesso") { cal.requestAccess() }
                                .buttonStyle(PillButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if cal.events.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").font(.system(size: 22)).foregroundStyle(Theme.yellow)
                        Text("Nenhum evento neste dia").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cal.events) { e in eventRow(e) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
    }

    private var weekStrip: some View {
        let today = calendar.startOfDay(for: Date())
        let days = (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let selected = calendar.isDate(d, inSameDayAs: cal.selectedDate)
                let isToday = calendar.isDateInToday(d)
                Button { withAnimation(.snappy) { cal.selectedDate = d } } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? Color.black.opacity(0.7) : Theme.secondary)
                        Text(d.formatted(.dateTime.day()))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? .black : (isToday ? Theme.orange : .white))
                    }
                    .frame(width: 40, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.orange : Theme.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func eventRow(_ e: DayEvent) -> some View {
        let now = Date()
        let ongoing = !e.allDay && e.start <= now && e.end > now
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(e.allDay ? "Dia inteiro"
                     : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if ongoing {
                Text("Agora").font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7).frame(height: 18)
                    .background(Capsule().fill(e.color.opacity(0.25))).foregroundStyle(e.color)
            }
            if let link = e.link {
                Button { NSWorkspace.shared.open(link) } label: {
                    Label("Entrar", systemImage: "video.fill")
                }
                .buttonStyle(PillButtonStyle(tint: e.color))
                .scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
    }
}

// MARK: - Bandeja de arquivos

struct TrayTabView: View {
    @EnvironmentObject var shelf: ShelfStore
    @Local private var targeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? Theme.orange : Color.white.opacity(0.18))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(targeted ? Theme.orange.opacity(0.08) : Color.clear))

            if shelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 26)).foregroundStyle(targeted ? Theme.orange : Theme.secondary)
                    Text("Arraste arquivos para cá").font(.system(size: 13, weight: .semibold))
                    Text("Eles ficam guardados no notch para você arrastar de volta quando quiser")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items) { item in ShelfItemView(item: item) }
                        }
                        .padding(.horizontal, 14)
                    }
                    VStack(spacing: 8) {
                        CircleIconButton(systemName: "airplayaudio", tint: Color(red: 0.4, green: 0.75, blue: 1),
                                         background: Color(red: 0.4, green: 0.75, blue: 1).opacity(0.18), size: 30) {
                            AirDrop.send(shelf.items.map(\.url))
                        }
                        .help("Enviar tudo por AirDrop")
                        CircleIconButton(systemName: "trash", tint: .white, size: 30) {
                            withAnimation { shelf.clear() }
                        }
                        .help("Limpar bandeja")
                    }
                    .padding(.trailing, 14)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { shelf.handleDrop($0) }
        .animation(.snappy, value: targeted)
    }
}

struct ShelfItemView: View {
    @EnvironmentObject var shelf: ShelfStore
    let item: ShelfItem
    @Local private var hover = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 52, height: 52)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(width: 84)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(hover ? Color.white.opacity(0.1) : .clear))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { withAnimation { shelf.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                        .foregroundStyle(.white, Color.gray.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(item.url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Enviar por AirDrop") { AirDrop.send([item.url]) }
            Button("Remover da bandeja") { shelf.remove(item) }
        }
    }
}


struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.orange
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14).frame(height: 28)
            .background(Capsule().fill(tint.opacity(0.2)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Capsule())
    }
}

/// Envio por AirDrop (abre a janela do sistema).
enum AirDrop {
    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }
}
