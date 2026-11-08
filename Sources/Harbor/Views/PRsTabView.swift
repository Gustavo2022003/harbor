import SwiftUI

/// Aba "PRs": seus pull requests (checks e revisões) e os que aguardam sua revisão.
struct PRsTabView: View {
    @EnvironmentObject var gh: GitHubStatus
    @AppStorage(GitHubStatus.alertsKey) private var alerts = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let error = gh.error, gh.mine.isEmpty && gh.toReview.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(Theme.orange)
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    column("Meus PRs", icon: "arrow.triangle.pull", prs: gh.mine,
                           empty: "Nenhum PR aberto 🎉")
                    ModuleDivider()
                    column("Aguardando sua revisão", icon: "eye", prs: gh.toReview,
                           empty: "Nada para revisar")
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pull Requests").font(.system(size: 13, weight: .bold))
            if gh.pendingCount > 0 {
                Label("\(gh.pendingCount) em CI", systemImage: "circle.dotted")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.yellow)
            }
            Spacer()
            Toggle("Avisos", isOn: $alerts).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            if let last = gh.lastUpdate {
                Text("atualizado \(last.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
            Button { gh.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(gh.loading ? 360 : 0))
                    .animation(gh.loading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: gh.loading)
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Theme.secondary)
            .help("Atualizar agora")
        }
        .frame(height: 22)
    }

    private func column(_ title: String, icon: String, prs: [GitHubStatus.PR], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("\(title) · \(prs.count)", systemImage: icon)
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.orange)
            if prs.isEmpty {
                Text(empty).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(prs) { pr in PRRow(pr: pr) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PRRow: View {
    @EnvironmentObject var gh: GitHubStatus
    let pr: GitHubStatus.PR
    @Local private var hover = false

    var body: some View {
        Button { gh.open(pr) } label: {
            HStack(spacing: 8) {
                checksIcon.frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(pr.repo)#\(pr.number)" + (pr.isDraft ? " · rascunho" : ""))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                reviewChip
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hover ? Color.white.opacity(0.1) : Theme.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(pr.url)
    }

    @ViewBuilder
    private var checksIcon: some View {
        switch pr.checks {
        case .success?: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .failure?, .error?: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .pending?, .expected?:
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                Image(systemName: "circle.dotted").foregroundStyle(Theme.yellow)
                    .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate * 90))
            }
        case nil: Image(systemName: "circle").foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder
    private var reviewChip: some View {
        switch pr.review {
        case .approved?: chip("Aprovado", Theme.green)
        case .changes?: chip("Mudanças", Theme.orange)
        case .required?: chip("Revisão", Theme.secondary)
        case nil: EmptyView()
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
