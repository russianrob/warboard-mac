import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        ZStack {
            switch vm.state {
            case .noKey:
                MessageView(icon: "key.slash", text: "Set your Torn API key in Settings.")
            case .loading:
                ProgressView().controlSize(.large)
            case .error(let msg):
                MessageView(icon: "exclamationmark.triangle.fill", text: msg)
            case .ready(let snap):
                ScrollView { DashboardBody(snap: snap).padding(16) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Status")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { vm.refresh() }) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
        }
        .onAppear { vm.bind(prefs: prefs); vm.start() }
        .onDisappear { vm.stop() }
    }
}

private struct MessageView: View {
    let icon: String; let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardBody: View {
    let snap: TornAPI.DashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(snap.playerName)\(snap.factionName.map { " · \($0)" } ?? "")")
                .font(.headline).foregroundStyle(.secondary)

            // Status banner — only when not Okay (hospital, jail, travel,
            // federal, abroad). Coloured by state.
            if snap.statusState.lowercased() != "okay" && !snap.statusState.isEmpty {
                StatusBanner(snap: snap)
            }

            // Bars
            BarRow(label: "Energy",  bar: snap.energy, color: Color(red: 0.13, green: 0.83, blue: 0.94))
            BarRow(label: "Nerve",   bar: snap.nerve,  color: .red)
            BarRow(label: "Happy",   bar: snap.happy,  color: .yellow)
            BarRow(label: "Life",    bar: snap.life,   color: .green)

            // Cooldowns — only render when active.
            if snap.drugSeconds > 0 || snap.medicalSeconds > 0 || snap.boosterSeconds > 0 {
                Divider().padding(.vertical, 4)
                Text("Cooldowns")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                if snap.drugSeconds > 0    { CooldownChip(label: "Drug",    seconds: snap.drugSeconds,    tint: .purple) }
                if snap.medicalSeconds > 0 { CooldownChip(label: "Medical", seconds: snap.medicalSeconds, tint: .red) }
                if snap.boosterSeconds > 0 { CooldownChip(label: "Booster", seconds: snap.boosterSeconds, tint: .green) }
            }

            if let dest = snap.travelDestination {
                Divider().padding(.vertical, 4)
                HStack {
                    Image(systemName: "airplane").foregroundColor(.cyan)
                    Text("Flying to \(dest)" +
                         (snap.travelSecondsLeft > 0 ? " — lands in \(formatDur(snap.travelSecondsLeft))" : ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.cyan)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct BarRow: View {
    let label: String
    let bar: TornAPI.Bar
    let color: Color

    var body: some View {
        let pct = bar.maximum > 0 ? Double(bar.current) / Double(bar.maximum) : 0
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(bar.current) / \(bar.maximum)").font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: pct).tint(color)
            if bar.fulltime > 0 && bar.current < bar.maximum {
                HStack {
                    Spacer()
                    Text("Full in \(formatDur(bar.fulltime))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CooldownChip: View {
    let label: String; let seconds: Int; let tint: Color
    var body: some View {
        HStack {
            Image(systemName: "clock.fill").foregroundColor(tint)
            Text("\(label): \(formatDur(seconds))")
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StatusBanner: View {
    let snap: TornAPI.DashboardSnapshot
    var body: some View {
        let color: Color = {
            switch snap.statusState.lowercased() {
            case "hospital": return .red
            case "jail":     return .purple
            case "traveling", "abroad": return .cyan
            case "federal":  return .orange
            default:         return .gray
            }
        }()
        HStack {
            Image(systemName: stateIcon).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.statusState).font(.subheadline.bold()).foregroundColor(color)
                if !snap.statusDescription.isEmpty {
                    Text(snap.statusDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if snap.statusSecondsLeft > 0 {
                Text(formatDur(snap.statusSecondsLeft))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundColor(color)
            }
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var stateIcon: String {
        switch snap.statusState.lowercased() {
        case "hospital": return "cross.case.fill"
        case "jail":     return "lock.fill"
        case "traveling", "abroad": return "airplane"
        case "federal":  return "building.columns.fill"
        default:         return "circle.fill"
        }
    }
}
