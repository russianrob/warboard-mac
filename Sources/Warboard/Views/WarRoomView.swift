import SwiftUI
import AppKit  // NSWorkspace.shared.open

struct WarRoomView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @StateObject private var vm = WarRoomViewModel()
    @State private var nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            switch vm.state {
            case .noKey:
                MessageView(icon: "key.slash", text: "Set your Torn API key in Settings.")
            case .loading:
                ProgressView().controlSize(.large)
            case .noWar:
                MessageView(icon: "shield.slash", text: "No active war.")
            case .active(let war):
                // Bind the target parameter explicitly — `$0` inside
                // `Task { … }` would otherwise resolve to the Task
                // closure (which has no params), not the outer
                // `(EnemyTarget) -> Void` we're satisfying.
                WarBody(war: war, poll: vm.poll, nowMs: nowMs,
                        onCall:   { target in Task { await vm.call(target) } },
                        onUncall: { target in Task { await vm.uncall(target) } })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { vm.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }.help("Refresh")
            }
        }
        .navigationTitle("War Room")
        .onAppear {
            vm.bind(prefs: prefs)
            vm.start()
        }
        .onDisappear { vm.stop() }
        .onReceive(ticker) { _ in
            nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }
}

private struct MessageView: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WarBody: View {
    let war: WarSnapshot
    let poll: WarPoll?
    let nowMs: Int64
    let onCall: (EnemyTarget) -> Void
    let onUncall: (EnemyTarget) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HeaderCard(war: war, poll: poll, nowMs: nowMs)
                .padding(12)
            Divider()
            TargetList(war: war, nowMs: nowMs, onCall: onCall, onUncall: onUncall)
        }
    }
}

private struct HeaderCard: View {
    let war: WarSnapshot
    let poll: WarPoll?
    let nowMs: Int64

    var body: some View {
        let myScore    = poll?.myScore    ?? war.myScore
        let enemyScore = poll?.enemyScore ?? war.enemyScore
        let target     = poll?.targetScore ?? war.currentTarget ?? 0
        let scoreColor: Color = (myScore == 0 && enemyScore == 0) ? .secondary
            : (myScore >= enemyScore ? .green : .red)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(war.enemyFactionName ?? poll?.enemyFactionName ?? "Enemy \(war.enemyFactionId)")")
                    .font(.headline)
                Spacer()
                if let online = poll?.ourFactionOnline {
                    Text("Us \(online)").foregroundStyle(.secondary).font(.caption)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(myScore) – \(enemyScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor)
                Spacer()
                if target > 0 {
                    Text("target \(target)")
                        .foregroundStyle(.secondary).font(.caption)
                }
            }
            ChainBar(war: war, poll: poll, nowMs: nowMs)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ChainBar: View {
    let war: WarSnapshot
    let poll: WarPoll?
    let nowMs: Int64

    var body: some View {
        let chain = poll?.chainCurrent ?? war.chainCurrent ?? 0
        let toSec = max(0, ((poll?.chainTimeout ?? war.chainTimeout) ?? 0))
        let cdSec = max(0, ((poll?.chainCooldown ?? war.chainCooldown) ?? 0))
        let nextBonus = nextChainMilestone(chain)
        let color: Color = {
            if chain == 0 || cdSec > 0 { return .secondary }
            if toSec <= 30 { return .red }
            if toSec <= 60 { return .orange }
            return .green
        }()
        let status: String = {
            if chain == 0 { return "no chain" }
            if cdSec > 0 { return "cooldown \(formatDur(Int(cdSec)))" }
            if toSec > 0 { return "breaks in \(formatDur(Int(toSec)))" }
            return "—"
        }()
        HStack {
            Label("Chain \(chain)/\(nextBonus)", systemImage: "link")
                .foregroundColor(color)
                .font(.subheadline.bold())
            Spacer()
            Text(status).foregroundColor(color).font(.caption.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.15), in: Capsule())
    }
}

private struct TargetList: View {
    let war: WarSnapshot
    let nowMs: Int64
    let onCall: (EnemyTarget) -> Void
    let onUncall: (EnemyTarget) -> Void

    var body: some View {
        let live = war.targets.map { t -> EnemyTarget in
            guard t.releaseAtMs > 0 else { return t }
            let remaining = max(0, (t.releaseAtMs - nowMs) / 1000)
            return EnemyTarget(
                id: t.id, name: t.name, level: t.level, status: t.status,
                description: t.description, untilSec: remaining,
                releaseAtMs: t.releaseAtMs, activity: t.activity,
                calledBy: t.calledBy, calledById: t.calledById
            )
        }
        let sorted = live.sorted { lhs, rhs in
            (priority(lhs), lhs.untilSec) < (priority(rhs), rhs.untilSec)
        }
        List(sorted) { t in
            TargetRow(target: t, onCall: onCall, onUncall: onUncall)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    /// Same priority bucket order as the Android `sortPriority` helper.
    private func priority(_ t: EnemyTarget) -> Double {
        if !(t.calledBy ?? "").isEmpty { return 5.0 }
        switch t.status.lowercased() {
        case "okay", "ok":          return t.activity == "online" ? 1.0 : 1.5
        case "hospital":            return 2.0
        case "traveling", "abroad": return 3.0
        case "jail":                return 4.0
        case "federal", "fallen":   return 7.0
        default:                    return 6.0
        }
    }
}

private struct TargetRow: View {
    let target: EnemyTarget
    let onCall: (EnemyTarget) -> Void
    let onUncall: (EnemyTarget) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(activityColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.subheadline.weight(.medium))
                Text("L\(target.level)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            StatusChip(target: target)
            if let caller = target.calledBy {
                Button("by \(caller)") { onUncall(target) }
                    .buttonStyle(.bordered).controlSize(.small)
            } else if target.status.lowercased() == "okay" {
                Button("Call") { onCall(target) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            if target.status.lowercased() == "okay" {
                Button("Attack") {
                    if let url = URL(string: "https://www.torn.com/loader.php?sid=attack&user2ID=\(target.id)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: "https://www.torn.com/profiles.php?XID=\(target.id)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var activityColor: Color {
        switch target.activity { case "online": return .green; case "idle": return .yellow; default: return .gray }
    }
}

private struct StatusChip: View {
    let target: EnemyTarget
    var body: some View {
        switch target.status.lowercased() {
        case "okay", "ok":
            EmptyView()
        case "hospital":
            chip(icon: "🏥", text: target.untilSec > 0 ? formatHms(Int(target.untilSec)) : "out", color: .red)
        case "jail":
            chip(icon: "🔒", text: target.untilSec > 0 ? formatHms(Int(target.untilSec)) : "out", color: .purple)
        case "traveling":
            let country = countryFromDescription(target.description)
            let arrow = target.description.hasPrefix("Returning") ? "←" : "→"
            chip(icon: "✈", text: "\(arrow) \(country)", color: .cyan)
        case "abroad":
            chip(icon: "🛬", text: countryFromAbroad(target.description), color: .cyan)
        default:
            chip(icon: "", text: target.status, color: .secondary)
        }
    }

    @ViewBuilder
    private func chip(icon: String, text: String, color: Color) -> some View {
        Text(icon.isEmpty ? text : "\(icon) \(text)")
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func countryFromDescription(_ s: String) -> String {
        if let r = s.range(of: "Traveling to ") { return String(s[r.upperBound...]) }
        if let r = s.range(of: "Returning to Torn from ") { return String(s[r.upperBound...]) }
        return s
    }
    private func countryFromAbroad(_ s: String) -> String {
        if let r = s.range(of: "In ") { return String(s[r.upperBound...]) }
        return s
    }
}

// MARK: - Helpers

func nextChainMilestone(_ current: Int) -> Int {
    let tiers = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000]
    return tiers.first(where: { current < $0 }) ?? tiers.last!
}

func formatDur(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    let sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
}

func formatHms(_ seconds: Int) -> String { formatDur(seconds) }
