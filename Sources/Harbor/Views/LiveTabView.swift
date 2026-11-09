import SwiftUI

/// Aba temporária "Agora": detalhes do que está em execução (Claude, downloads, timer, reunião).
/// Só aparece na barra enquanto há algo rodando; as outras abas continuam ao lado.
struct LiveTabView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var claude: ClaudeActivity

    static func tint(_ kind: LiveKind) -> Color {
        switch kind {
        case .claude: return ClaudeActivity.claudeColor
        case .download: return LiveDownloadsCard.tint
        case .timer: return Theme.orange
        case .meeting: return Color(red: 0.39, green: 0.82, blue: 1)
        }
    }

    /// Um cartão por sessão do Claude; um para cada outra atividade.
    private enum Card: Identifiable {
        case claude(String), download, timer, meeting
        var id: String {
            switch self {
            case .claude(let s): return "claude-" + s
            case .download: return "download"
            case .timer: return "timer"
            case .meeting: return "meeting"
            }
        }
    }

    private var cards: [Card] {
        vm.live.flatMap { kind -> [Card] in
            switch kind {
            case .claude: return claude.liveSessions.map { .claude($0.id) }
            case .download: return [.download]
            case .timer: return [.timer]
            case .meeting: return [.meeting]
            }
        }
    }

    var body: some View {
        let cards = cards
        Group {
            if cards.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text("Nada em execução agora").font(.system(size: 13, weight: .semibold))
                    Text("Esta aba aparece sozinha quando o Claude, um download, o timer ou uma reunião estiverem rodando.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cards.count <= 3 {
                HStack(spacing: 10) {
                    ForEach(cards) { card($0, wide: cards.count == 1) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { card($0, wide: false).frame(width: 300) }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: cards.map(\.id))
    }

    @ViewBuilder
    private func card(_ c: Card, wide: Bool) -> some View {
        Group {
            switch c {
            case .claude(let id): LiveClaudeCard(sessionID: id, wide: wide)
            case .download: LiveDownloadsCard()
            case .timer: LiveTimerCard()
            case .meeting: LiveMeetingCard()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

// MARK: - Peças comuns

/// Ponto pulsando (aba "Agora" e cabeçalho dos cartões).
struct LiveDot: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let t = (sin(ctx.date.timeIntervalSinceReferenceDate * 3.2) + 1) / 2
            ZStack {
                Circle().fill(color.opacity(0.35 * (1 - t))).frame(width: 7 + 7 * t, height: 7 + 7 * t)
                Circle().fill(color).frame(width: 7, height: 7)
            }
            .frame(width: 14, height: 14)
        }
    }
}

private struct LiveCardShell<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.16), Theme.card],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.28)))
    }
}

private struct LiveHeader<Leading: View, Trailing: View>: View {
    var title: String
    var status: String?
    var tint: Color
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 7) {
            leading.frame(width: 18, height: 18)
            Text(title).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
            if let status {
                Text(status)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7).frame(height: 17)
                    .background(Capsule().fill(tint.opacity(0.16)))
                    .fixedSize()
            }
            Spacer(minLength: 4)
            trailing
        }
    }
}

private struct LiveButton: View {
    var title: String
    var icon: String
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ThinBar: View {
    var fraction: Double?
    var tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                if let fraction {
                    Capsule().fill(tint).frame(width: max(5, g.size.width * min(1, max(0, fraction))))
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(tint).frame(width: g.size.width * 0.3)
                            .offset(x: (g.size.width * 1.3) * t - g.size.width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 5)
        .animation(.snappy, value: fraction)
    }
}

// MARK: - Claude

private struct LiveClaudeCard: View {
    @EnvironmentObject var claude: ClaudeActivity
    let sessionID: String
    let wide: Bool
    private let tint = ClaudeActivity.claudeColor

    var body: some View {
        if let s = claude.sessions[sessionID] {
            LiveCardShell(tint: tint) {
                LiveHeader(title: s.project, status: s.waiting ? "Esperando você" : "Trabalhando", tint: tint) {
                    if s.waiting {
                        Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                    } else {
                        ClaudeSpinner()
                    }
                } trailing: {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(ClaudeActivity.duration(ctx.date.timeIntervalSince(s.since)))
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(tint)
                    }
                }
                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) { promptView(s); toolRow(s) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ÚLTIMA MENSAGEM").font(.system(size: 9.5, weight: .bold)).tracking(0.6)
                                .foregroundStyle(Theme.secondary)
                            Text(s.lastText ?? "—").font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.25)))
                    }
                    buttons(s)
                } else {
                    promptView(s)
                    toolRow(s)
                    Spacer(minLength: 0)
                    buttons(s)
                }
            }
        }
    }

    @ViewBuilder
    private func promptView(_ s: ClaudeActivity.Session) -> some View {
        Text(s.prompt.isEmpty ? "Sessão do Claude Code" : "“\(s.prompt)”")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .lineLimit(2)
    }

    private func toolRow(_ s: ClaudeActivity.Session) -> some View {
        HStack(spacing: 5) {
            Image(systemName: s.waiting ? "exclamationmark.bubble.fill" : "wrench.and.screwdriver.fill")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            Text(s.waiting ? "Volte ao terminal para responder" : ClaudeActivity.toolLabel(s.tool))
                .font(.system(size: 11.5, weight: .semibold))
                .fixedSize()
            if !s.waiting, let d = s.toolDetail {
                Text(d).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if s.toolCount > 0 {
                Text("\(s.toolCount) \(s.toolCount == 1 ? "ação" : "ações")")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary).fixedSize()
            }
        }
    }

    private func buttons(_ s: ClaudeActivity.Session) -> some View {
        HStack(spacing: 6) {
            if !s.cwd.isEmpty {
                LiveButton(title: "Abrir pasta", icon: "folder.fill") { claude.reveal(s) }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Downloads

struct LiveDownloadsCard: View {
    @EnvironmentObject var downloads: DownloadsMonitor
    static let tint = Color(red: 0.4, green: 0.75, blue: 1)

    var body: some View {
        let items = downloads.items
        LiveCardShell(tint: Self.tint) {
            LiveHeader(title: items.count == 1 ? "Baixando" : "Baixando \(items.count) arquivos",
                       status: nil, tint: Self.tint) {
                DownloadRing(fraction: downloads.active?.fraction)
            } trailing: {
                if let f = downloads.active?.fraction {
                    Text("\(Int(f * 100))%").font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(Self.tint)
                        .contentTransition(.numericText())
                }
            }
            ForEach(items.prefix(items.count == 1 ? 1 : 2)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    ThinBar(fraction: item.fraction, tint: Self.tint)
                    Text(Self.detail(item)).font(.system(size: 10.5)).monospacedDigit()
                        .foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            LiveButton(title: "Abrir Downloads", icon: "arrow.down.circle.fill") {
                NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
            }
        }
    }

    static func detail(_ i: DownloadsMonitor.Item) -> String {
        var parts = [DownloadsMonitor.format(bytes: i.bytes) + (i.total.map { " de " + DownloadsMonitor.format(bytes: $0) } ?? "")]
        if i.speed > 0 {
            parts.append(DownloadsMonitor.format(bytes: Int64(i.speed)) + "/s")
            if let total = i.total, total > i.bytes {
                parts.append("~" + ClaudeActivity.duration(Double(total - i.bytes) / i.speed) + " restantes")
            }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Timer

private struct LiveTimerCard: View {
    @EnvironmentObject var timer: FocusTimer
    private let tint = Theme.orange

    var body: some View {
        LiveCardShell(tint: tint) {
            LiveHeader(title: timer.mode == .focus ? "Foco" : "Pausa",
                       status: timer.isRunning ? "Rodando" : "Pausado", tint: tint) {
                Image(systemName: timer.mode == .focus ? "timer" : "cup.and.saucer.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            } trailing: { EmptyView() }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timer.formatted)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                    .contentTransition(.numericText())
                Text("de \(timer.selectedMinutes) min").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            ThinBar(fraction: timer.progress, tint: tint)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                LiveButton(title: timer.isRunning ? "Pausar" : "Continuar",
                           icon: timer.isRunning ? "pause.fill" : "play.fill", tint: tint) { timer.toggle() }
                LiveButton(title: "Zerar", icon: "arrow.counterclockwise") { timer.reset() }
            }
        }
    }
}

// MARK: - Reunião

private struct LiveMeetingCard: View {
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        if let m = calendar.nextMeeting {
            LiveCardShell(tint: m.color) {
                LiveHeader(title: m.title, status: nil, tint: m.color) {
                    Image(systemName: "video.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(m.color)
                } trailing: {
                    TimelineView(.periodic(from: .now, by: 15)) { ctx in
                        Text(Self.relative(m.start, now: ctx.date))
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(m.color)
                    }
                }
                Text(m.start.formatted(date: .omitted, time: .shortened) + " – " + m.end.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let link = m.link {
                        LiveButton(title: "Entrar", icon: "video.fill", tint: m.color) { NSWorkspace.shared.open(link) }
                    }
                    LiveButton(title: "Ver agenda", icon: "calendar") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.tab = .calendar }
                    }
                }
            }
        }
    }

    static func relative(_ start: Date, now: Date) -> String {
        let mins = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if mins > 0 { return "em \(mins) min" }
        let ago = Int(now.timeIntervalSince(start) / 60)
        return ago < 1 ? "agora" : "há \(ago) min"
    }
}
