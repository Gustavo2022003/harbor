import SwiftUI

/// Aba "Odômetro": quanto o mouse já "andou".
struct OdometerTabView: View {
    @EnvironmentObject var odo: MouseOdometer

    var body: some View {
        HStack(spacing: 22) {
            mouseColumn.frame(width: 190, alignment: .leading)
            ModuleDivider()
            counters.frame(maxWidth: .infinity)
            ModuleDivider()
            controls.frame(width: 250, alignment: .leading)
        }
        .padding(.horizontal, 10)
    }

    // MARK: Mouse + velocidade

    private var mouseColumn: some View {
        let moving = odo.speed > 0.002
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(Theme.orange.opacity(moving ? 0.22 : 0.1)).frame(width: 54, height: 54)
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                    .rotationEffect(.degrees(moving ? -8 : 0))
                    .offset(x: moving ? 2 : 0)
            }
            .animation(moving ? .easeInOut(duration: 0.18).repeatForever(autoreverses: true) : .snappy,
                       value: moving)
            Text("Odômetro do mouse").font(.system(size: 14, weight: .bold))
            HStack(spacing: 5) {
                Image(systemName: "speedometer").foregroundStyle(Theme.secondary)
                Text(odo.formatSpeed(odo.speed))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: odo.speed)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondary)

            Button { withAnimation(.snappy) { odo.pinned.toggle() } } label: {
                Label(odo.pinned ? "Fixado no notch" : "Fixar no notch",
                      systemImage: odo.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(PillButtonStyle(tint: odo.pinned ? Theme.orange : .white))
            .help("Mostra uma bolha ao lado do island com a distância de hoje")
        }
    }

    // MARK: Hoje / Total

    private var counters: some View {
        let today = odo.parts(odo.todayMeters)
        return VStack(spacing: 6) {
            Text("HOJE").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(Theme.orange).tracking(1.5)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(today.value)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: today.value)
                Text(today.suffix)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                Text("Total:").foregroundStyle(Theme.secondary)
                Text(odo.format(odo.totalMeters))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: odo.format(odo.totalMeters))
                Text("·").foregroundStyle(Theme.secondary)
                Text(odo.comparison(odo.totalMeters)).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
        }
    }

    // MARK: Unidades + zerar

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unidade").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(DistanceUnit.allCases) { u in
                    let selected = odo.unit == u
                    Button { withAnimation(.snappy) { odo.unit = u } } label: {
                        Text(u.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(selected ? Theme.orange : Color.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Capsule().fill(selected ? Theme.orange.opacity(0.22) : Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack(spacing: 6) {
                Button("Zerar hoje") { withAnimation(.snappy) { odo.resetToday() } }
                    .buttonStyle(PillButtonStyle(tint: .white))
                Button("Zerar tudo") { withAnimation(.snappy) { odo.resetAll() } }
                    .buttonStyle(PillButtonStyle(tint: .red))
            }
            .scaleEffect(0.9, anchor: .leading)
        }
    }
}
