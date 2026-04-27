import Foundation
import Combine

/// War Room state holder. Polls `/api/faction/<fid>/war` + `/api/poll`
/// every 15 s. Mirrors the Android `WarRoomViewModel` shape so future
/// features (heatmap, scout report, engines) plug in symmetrically.
@MainActor
final class WarRoomViewModel: ObservableObject {
    enum State: Equatable {
        case noKey, loading, noWar, active(WarSnapshot)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var poll: WarPoll?
    @Published private(set) var lastPolledAt: Date?
    /// Scout report — loaded on demand when the Report sub-tab opens.
    @Published private(set) var scoutReport: ScoutReport?
    @Published private(set) var scoutLoading = false
    /// Both faction heatmaps. Refreshed each war-poll tick.
    @Published private(set) var ourHeatmap:  [Int: [Int: HeatmapCell]] = [:]
    @Published private(set) var theirHeatmap: [Int: [Int: HeatmapCell]] = [:]
    /// FFScouter battle-stat estimates per enemy id (server-cached 30 min).
    @Published private(set) var enemyStats: [String: Int64] = [:]
    /// FFS player-flights data per traveling enemy.
    @Published private(set) var travelInfo: [String: TravelInfo] = [:]
    /// Last shout result — nil = no shout sent yet, .ok = success snackbar.
    @Published var shoutResult: String?

    /// Bound at .task time from the View — see `bind(prefs:)`. The VM
    /// can't take prefs at init because @StateObject is constructed
    /// before @EnvironmentObject is available. Until binding lands the
    /// VM stays in the .loading state and the polling loop is a no-op.
    private var prefs: PrefsStore?
    private var auth: AuthRepository?
    private var task: Task<Void, Never>?
    /// Per-enemy releaseAtMs from the previous tick — drives the
    /// monotonic guard so a stale poll can't bump release times forward.
    private var lastReleaseAtMs: [String: Int64] = [:]

    init() { }

    func bind(prefs: PrefsStore) {
        self.prefs = prefs
        self.auth = AuthRepository(prefs: prefs)
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
    }

    func refresh() {
        Task { await tick() }
    }

    func call(_ target: EnemyTarget) async {
        await callTarget(target, action: "call")
    }
    func uncall(_ target: EnemyTarget) async {
        await callTarget(target, action: "uncall")
    }

    private func callTarget(_ target: EnemyTarget, action: String) async {
        guard case .active(let war) = state,
              let prefs = prefs, let auth = auth,
              let a = await auth.ensureAuth() else { return }
        _ = await WarboardAPI.callTarget(
            baseUrl: prefs.baseUrl, jwt: a.token,
            warId: war.warId, action: action,
            targetId: target.id, targetName: target.name
        )
        await tick()
    }

    private func tick() async {
        guard let prefs = prefs, let auth = auth else { return }
        if prefs.apiKey.isEmpty { state = .noKey; return }
        guard let a = await auth.ensureAuth() else { state = .noKey; return }
        let wars = await WarboardAPI.fetchWars(
            baseUrl: prefs.baseUrl, factionId: a.factionId, jwt: a.token
        )
        lastPolledAt = Date()
        if wars.isEmpty { state = .noWar; return }
        let merged = mergeMonotonic(wars[0])
        state = .active(merged)
        if let fresh = await WarboardAPI.fetchPoll(
            baseUrl: prefs.baseUrl, jwt: a.token, warId: merged.warId
        ) {
            poll = fresh
        }
        // Both faction heatmaps — same endpoint, different factionId.
        // Diverging-color grid in the Heatmap sub-tab consumes both.
        ourHeatmap = await WarboardAPI.fetchHeatmap(
            baseUrl: prefs.baseUrl, jwt: a.token, factionId: a.factionId
        )
        if !merged.enemyFactionId.isEmpty {
            theirHeatmap = await WarboardAPI.fetchHeatmap(
                baseUrl: prefs.baseUrl, jwt: a.token, factionId: merged.enemyFactionId
            )
        }
        // Enemy stats — fetch once per war (server-cached). Travel info
        // refreshes every tick so countdowns stay accurate near landing.
        if enemyStats.isEmpty {
            enemyStats = await WarboardAPI.fetchEnemyStats(
                baseUrl: prefs.baseUrl, jwt: a.token, warId: merged.warId
            )
        }
        travelInfo = await WarboardAPI.fetchTravelInfo(
            baseUrl: prefs.baseUrl, jwt: a.token, warId: merged.warId
        )
    }

    /// Fire a faction-wide shout — calls /api/broadcast. Server gates
    /// on leader/banker; non-leaders get the rejection in shoutResult.
    func sendShout(_ message: String) {
        Task {
            guard let prefs = prefs, let auth = auth,
                  case .active(let war) = state,
                  let a = await auth.ensureAuth() else { return }
            let result = await WarboardAPI.sendBroadcast(
                baseUrl: prefs.baseUrl, jwt: a.token,
                warId: war.warId, message: message
            )
            switch result {
            case .ok:                shoutResult = "Shout sent"
            case .error(let msg):    shoutResult = "Shout failed: \(msg)"
            }
        }
    }

    /// Lazy scout-report fetch fired when the Report sub-tab opens. The
    /// report endpoint hits FFScouter + Torn API server-side and is
    /// rate-limited to a few requests per minute, so we don't auto-poll.
    func loadScoutReport() {
        Task {
            guard let prefs = prefs, let auth = auth,
                  case .active(let war) = state,
                  let a = await auth.ensureAuth() else { return }
            scoutLoading = true
            scoutReport = await WarboardAPI.fetchScoutReport(
                baseUrl: prefs.baseUrl, jwt: a.token, warId: war.warId
            )
            scoutLoading = false
        }
    }

    /// Same min-of-(prev, new) trick as the Android client — keeps
    /// hospital / jail countdowns from rebounding when Torn's API
    /// returns a stale "still N seconds" value mid-tick.
    private func mergeMonotonic(_ fresh: WarSnapshot) -> WarSnapshot {
        let rebased = fresh.targets.map { t -> EnemyTarget in
            let key = "\(t.id)|\(t.status)"
            guard t.releaseAtMs > 0 else {
                lastReleaseAtMs.removeValue(forKey: key)
                return t
            }
            let previous = lastReleaseAtMs[key] ?? 0
            let winner = previous > 0 ? min(previous, t.releaseAtMs) : t.releaseAtMs
            lastReleaseAtMs[key] = winner
            if winner == t.releaseAtMs { return t }
            return EnemyTarget(
                id: t.id, name: t.name, level: t.level, status: t.status,
                description: t.description, untilSec: t.untilSec,
                releaseAtMs: winner, activity: t.activity,
                calledBy: t.calledBy, calledById: t.calledById
            )
        }
        let liveKeys = Set(fresh.targets.map { "\($0.id)|\($0.status)" })
        lastReleaseAtMs = lastReleaseAtMs.filter { liveKeys.contains($0.key) }
        return WarSnapshot(
            warId: fresh.warId, enemyFactionId: fresh.enemyFactionId,
            enemyFactionName: fresh.enemyFactionName,
            myScore: fresh.myScore, enemyScore: fresh.enemyScore,
            warStart: fresh.warStart, warOrigTarget: fresh.warOrigTarget,
            currentTarget: fresh.currentTarget,
            chainCurrent: fresh.chainCurrent, chainTimeout: fresh.chainTimeout,
            chainCooldown: fresh.chainCooldown,
            targets: rebased
        )
    }
}
