import SwiftUI
import AppKit  // NSWorkspace.shared.open

enum WarSubTab: String, CaseIterable, Identifiable {
    case targets, report, heatmap
    var id: String { rawValue }
    var label: String {
        switch self { case .targets: return "Targets"; case .report: return "Report"; case .heatmap: return "Heatmap" }
    }
}

struct WarRoomView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @StateObject private var vm = WarRoomViewModel()
    @State private var nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    @State private var subTab: WarSubTab = .targets
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $subTab) {
                ForEach(WarSubTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.top, 8)

            switch vm.state {
            case .noKey:
                MessageView(icon: "key.slash", text: "Set your Torn API key in Settings.")
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noWar:
                MessageView(icon: "shield.slash", text: "No active war.")
            case .active(let war):
                switch subTab {
                case .targets:
                    WarBody(war: war, poll: vm.poll, nowMs: nowMs,
                            onCall:   { target in Task { await vm.call(target) } },
                            onUncall: { target in Task { await vm.uncall(target) } })
                case .report:
                    ReportTab(report: vm.scoutReport, loading: vm.scoutLoading,
                              onLoad: { vm.loadScoutReport() })
                case .heatmap:
                    HeatmapTab(ours: vm.ourHeatmap, theirs: vm.theirHeatmap)
                }
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
        .onChange(of: subTab) { _, new in
            // First time the user opens the report tab, kick the fetch.
            if new == .report && vm.scoutReport == nil && !vm.scoutLoading {
                vm.loadScoutReport()
            }
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

// MARK: - Report tab

struct ReportTab: View {
    let report: ScoutReport?
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("War analysis").font(.title3.bold())
                    Spacer()
                    Button(loading ? "Refreshing…" : "Refresh", action: onLoad)
                        .disabled(loading)
                }
                if let r = report {
                    ReportBody(r: r)
                } else if loading {
                    ProgressView().padding()
                } else {
                    Text("No report yet — tap Refresh.").foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }
}

private struct ReportBody: View {
    let r: ScoutReport
    private let ourColor   = Color.green
    private let enemyColor = Color.red

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Win probability headline
            let winColor: Color = r.winProbability >= 65 ? .green
                : r.winProbability >= 45 ? .yellow : .red
            HStack {
                Text("Win probability").foregroundColor(winColor).font(.subheadline.bold())
                Spacer()
                Text("\(r.winProbability)%").font(.system(size: 32, weight: .bold)).foregroundColor(winColor)
            }
            .padding(12)
            .background(winColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text(r.hasEstimates
                 ? "Based on FFScouter battle-stat estimates"
                 : "Based on level only — no FFS estimates available")
                .font(.caption.bold())
                .foregroundColor(r.hasEstimates ? .green : .secondary)

            if !r.winReasoning.isEmpty {
                ForEach(r.winReasoning, id: \.self) { line in
                    Text("• \(line)").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            sectionCard("War Overview") {
                CompareHeader(left: r.our.factionName, right: r.enemy.factionName,
                              leftColor: ourColor, rightColor: enemyColor)
                CompareRow(label: "Members",    left: "\(r.our.members)",   right: "\(r.enemy.members)")
                CompareRow(label: "Respect",    left: fmtNum(r.our.respect), right: fmtNum(r.enemy.respect))
                CompareRow(label: "Best chain", left: fmtNum(r.our.bestChain), right: fmtNum(r.enemy.bestChain))
                CompareRow(label: "Age",        left: "\(r.our.age)d",      right: "\(r.enemy.age)d")
            }

            if !r.matchups.isEmpty {
                sectionCard("Top-End Comparison") {
                    ForEach(r.matchups) { mu in
                        MatchupRow(mu: mu, ourColor: ourColor, enemyColor: enemyColor)
                    }
                }
            }

            sectionCard("Stat Tier Breakdown") {
                let max = Swift.max(
                    r.our.tiers.s, r.our.tiers.a, r.our.tiers.b, r.our.tiers.c, r.our.tiers.d,
                    r.enemy.tiers.s, r.enemy.tiers.a, r.enemy.tiers.b, r.enemy.tiers.c, r.enemy.tiers.d, 1
                )
                let rows: [(String, Int, Int, String)] = [
                    ("S", r.our.tiers.s, r.enemy.tiers.s, r.tierDescriptions.s),
                    ("A", r.our.tiers.a, r.enemy.tiers.a, r.tierDescriptions.a),
                    ("B", r.our.tiers.b, r.enemy.tiers.b, r.tierDescriptions.b),
                    ("C", r.our.tiers.c, r.enemy.tiers.c, r.tierDescriptions.c),
                    ("D", r.our.tiers.d, r.enemy.tiers.d, r.tierDescriptions.d),
                ]
                ForEach(rows, id: \.0) { row in
                    TierBarRow(label: row.0, ours: row.1, enemy: row.2, max: max,
                               ourColor: ourColor, enemyColor: enemyColor)
                    Text(row.3).font(.caption2).foregroundStyle(.secondary)
                        .padding(.leading, 22)
                }
            }

            sectionCard("Activity") {
                CompareHeader(left: r.our.factionName, right: r.enemy.factionName,
                              leftColor: ourColor, rightColor: enemyColor)
                CompareRow(label: "Online",      left: "\(r.our.online)",       right: "\(r.enemy.online)")
                CompareRow(label: "Idle",        left: "\(r.our.idle)",         right: "\(r.enemy.idle)")
                CompareRow(label: "Offline",     left: "\(r.our.offline)",      right: "\(r.enemy.offline)")
                CompareRow(label: "Combat ready", left: "\(r.our.activeCombat)", right: "\(r.enemy.activeCombat)")
            }

            if !r.safeHits.thresholds.isEmpty {
                sectionCard("Safe Hits") {
                    ForEach(r.safeHits.thresholds) { th in
                        HStack {
                            Text(th.label).bold().frame(width: 84, alignment: .leading)
                            Text(th.desc).foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Text("\(th.ourCount) us · \(th.enemyFarmable) them")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Roster that can hit: \(r.safeHits.ourCanHitPct)% · Enemy farmable: \(r.safeHits.enemyFarmablePct)%")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let bp = r.battlePlan {
                sectionCard("Tactical Battle Plan") {
                    Text("Phase: \(bp.warPhase.capitalized)").foregroundColor(.yellow).font(.subheadline.bold())
                    if let p = bp.opening { phaseSection(label: "Phase 1 — Opening", phase: p, accent: .green) }
                    if let p = bp.midWar  { phaseSection(label: "Phase 2 — Mid-war", phase: p, accent: .yellow) }
                    if let p = bp.endgame { phaseSection(label: "Phase 3 — Endgame", phase: p, accent: .orange) }
                    if !bp.keyPermaTargets.isEmpty {
                        Text("Key perma-targets").foregroundColor(.red).font(.subheadline.bold())
                        ForEach(bp.keyPermaTargets) { p in
                            Text("  • \(p.name) (L\(p.level), \(p.statsFormatted))")
                                .font(.caption)
                        }
                    }
                    if !bp.ignore.isEmpty {
                        Text("Avoid (\(bp.ignore.count))").foregroundStyle(.secondary).font(.subheadline.bold())
                        ForEach(bp.ignore) { p in
                            Text("  • \(p.name) (L\(p.level), \(p.statsFormatted))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold()).foregroundColor(.accentColor)
            content()
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func phaseSection(label: String, phase: BattlePhase, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundColor(accent).font(.subheadline.bold())
            Text(phase.description).font(.caption)
            if !phase.targets.isEmpty {
                Text("Hit (\(phase.targets.count))").font(.caption.bold()).foregroundColor(.red)
                ForEach(phase.targets) { p in
                    Text("  • \(p.name) (L\(p.level), \(p.statsFormatted))").font(.caption2)
                }
            }
            if !phase.ourPlayers.isEmpty {
                Text("Deploy (\(phase.ourPlayers.count))").font(.caption.bold()).foregroundColor(.green)
                ForEach(phase.ourPlayers) { p in
                    Text("  • \(p.name) (L\(p.level), \(p.statsFormatted))").font(.caption2)
                }
            }
        }
        .padding(8)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CompareHeader: View {
    let left: String; let right: String
    let leftColor: Color; let rightColor: Color
    var body: some View {
        HStack {
            Text("").frame(width: 100, alignment: .leading)
            Text(left).foregroundColor(leftColor).font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(right).foregroundColor(rightColor).font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CompareRow: View {
    let label: String; let left: String; let right: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.caption)
                .frame(width: 100, alignment: .leading)
            Text(left).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            Text(right).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MatchupRow: View {
    let mu: Matchup
    let ourColor: Color; let enemyColor: Color
    var body: some View {
        HStack {
            Text("\(mu.rank)").foregroundStyle(.secondary).font(.caption).frame(width: 24)
            VStack(alignment: .leading) {
                Text(mu.ours?.name ?? "—").foregroundColor(ourColor).font(.subheadline.weight(.medium))
                Text(mu.ours.map { "L\($0.level) · \($0.statsFormatted)" } ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(advantageSymbol)
                .foregroundColor(advantageColor)
                .font(.subheadline.bold())
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(mu.theirs?.name ?? "—").foregroundColor(enemyColor).font(.subheadline.weight(.medium))
                Text(mu.theirs.map { "L\($0.level) · \($0.statsFormatted)" } ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var advantageSymbol: String {
        switch mu.advantage { case "ours": return "◀"; case "theirs": return "▶"; default: return "•" }
    }
    private var advantageColor: Color {
        switch mu.advantage { case "ours": return ourColor; case "theirs": return enemyColor; default: return .secondary }
    }
}

private struct TierBarRow: View {
    let label: String
    let ours: Int; let enemy: Int; let max: Int
    let ourColor: Color; let enemyColor: Color
    var body: some View {
        let ourFrac = max > 0 ? Double(ours) / Double(max) : 0
        let enemyFrac = max > 0 ? Double(enemy) / Double(max) : 0
        HStack {
            Text(label).font(.subheadline.bold()).frame(width: 22)
            HStack(spacing: 4) {
                Spacer()
                Text("\(ours)").foregroundColor(ourColor).font(.caption.bold())
                Capsule().fill(ourColor.opacity(0.6))
                    .frame(maxWidth: 100 * ourFrac, minHeight: 8, maxHeight: 10)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Capsule().fill(enemyColor.opacity(0.6))
                    .frame(maxWidth: 100 * enemyFrac, minHeight: 8, maxHeight: 10)
                Text("\(enemy)").foregroundColor(enemyColor).font(.caption.bold())
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private func fmtNum(_ n: Int) -> String {
    if n <= 0 { return "—" }
    return n.formatted(.number.grouping(.automatic))
}

// MARK: - Heatmap tab

struct HeatmapTab: View {
    let ours: [Int: [Int: HeatmapCell]]
    let theirs: [Int: [Int: HeatmapCell]]

    var body: some View {
        if ours.isEmpty && theirs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("No heatmap samples yet — warboard collects activity over time.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView { content }
        }
    }

    private var content: some View {
        let avg: ([Int: [Int: HeatmapCell]], Int, Int) -> Double = { hm, d, h in
            guard let c = hm[d]?[h], c.samples > 0 else { return 0 }
            return Double(c.total) / Double(c.samples)
        }
        let maxSingle = (1...7).flatMap { d in (0...23).map { h in
            Swift.max(avg(ours, d, h), avg(theirs, d, h))
        }}.max() ?? 1.0
        let days: [(Int, String)] = [
            (1,"Mon"),(2,"Tue"),(3,"Wed"),(4,"Thu"),(5,"Fri"),(6,"Sat"),(7,"Sun")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activity heatmap — us vs them").font(.title3.bold())
            Text("Diverging color per hour. Brighter green = our side more active; brighter red = enemy more active.")
                .font(.caption).foregroundStyle(.secondary)

            // Hour labels
            HStack(spacing: 1) {
                Text("").frame(width: 36)
                ForEach(0..<24, id: \.self) { h in
                    Text(h % 3 == 0 ? "\(h)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(days, id: \.0) { (day, label) in
                HStack(spacing: 1) {
                    Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        let o = avg(ours, day, h)
                        let t = avg(theirs, day, h)
                        let delta = o - t
                        let intensity = Swift.min(1.0, abs(delta) / Swift.max(maxSingle, 1.0))
                        let noData = ours[day]?[h] == nil && theirs[day]?[h] == nil
                        let tint: Color = {
                            if noData { return Color.gray.opacity(0.05) }
                            if delta > 0 { return Color.green.opacity(0.15 + intensity * 0.75) }
                            if delta < 0 { return Color.red.opacity(0.15 + intensity * 0.75) }
                            return Color.gray.opacity(0.10)
                        }()
                        Rectangle().fill(tint)
                            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
        }
        .padding(16)
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
