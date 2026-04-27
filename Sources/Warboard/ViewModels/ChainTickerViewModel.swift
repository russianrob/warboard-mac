import Foundation
import Combine

/// Menu-bar status item's chain ticker. Pulls /v2/faction?selections=
/// chain directly from Torn API on a 30 s loop — same path the
/// warboard-native Android client uses for the in-app chain bar. No
/// warboard dependency, so the ticker stays accurate even when the
/// warboard server is down. Stamps absolute deadlines + applies a
/// script-style monotonic guard so a stale Torn cache returning a
/// higher timeout can't bump the displayed countdown back up.
@MainActor
final class ChainTickerViewModel: ObservableObject {
    @Published private(set) var chainCurrent: Int = 0
    @Published private(set) var nextMilestone: Int = 10
    @Published private(set) var timeoutDeadlineMs: Int64 = 0
    @Published private(set) var cooldownDeadlineMs: Int64 = 0
    @Published private(set) var inActiveWar: Bool = false

    private let prefs: PrefsStore
    private var task: Task<Void, Never>?
    /// Monotonic guard state — clears when chain count flips (new hit
    /// or chain breaks → trust the new deadline absolutely).
    private var lastChainCount: Int?

    init(prefs: PrefsStore) {
        self.prefs = prefs
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    private func tick() async {
        guard !prefs.apiKey.isEmpty,
              let chain = await TornAPI.fetchFactionChain(apiKey: prefs.apiKey) else {
            inActiveWar = false; chainCurrent = 0
            timeoutDeadlineMs = 0; cooldownDeadlineMs = 0
            return
        }
        // chain.max == 0 means "no current chain bonus tier" — Torn
        // still returns 0/0/0 outside of war chains. Treat that as
        // "in active war" only when chain ≥ 1 (mirrors the Android
        // client's "no chain" rendering).
        inActiveWar = true
        let countChanged = lastChainCount != chain.current
        chainCurrent = chain.current
        nextMilestone = nextChainMilestone(chain.current)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let incomingTimeoutDl  = chain.timeout  > 0 ? now + chain.timeout  * 1000 : 0
        let incomingCooldownDl = chain.cooldown > 0 ? now + chain.cooldown * 1000 : 0

        // Same min-of-(prev, new) guard the Android VM uses. Reset
        // when count changes — a fresh hit legitimately bumps the timer.
        if countChanged || timeoutDeadlineMs == 0 {
            timeoutDeadlineMs = incomingTimeoutDl
        } else if incomingTimeoutDl == 0 {
            timeoutDeadlineMs = 0
        } else {
            timeoutDeadlineMs = min(timeoutDeadlineMs, incomingTimeoutDl)
        }
        if countChanged || cooldownDeadlineMs == 0 {
            cooldownDeadlineMs = incomingCooldownDl
        } else if incomingCooldownDl == 0 {
            cooldownDeadlineMs = 0
        } else {
            cooldownDeadlineMs = min(cooldownDeadlineMs, incomingCooldownDl)
        }
        lastChainCount = chain.current
    }
}
