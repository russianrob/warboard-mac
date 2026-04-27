import Foundation
import Combine

/// Tiny VM dedicated to the menu-bar status item — pulls the war's
/// chain data on a 30 s loop directly from /api/faction/<fid>/war (no
/// /api/poll dependency, same path the warboard-native Android client
/// uses for the chain bar). Exposes the absolute timeoutDeadlineMs so
/// the menu-bar label can derive seconds remaining each frame without
/// the value drifting between fetches.
@MainActor
final class ChainTickerViewModel: ObservableObject {
    @Published private(set) var chainCurrent: Int = 0
    @Published private(set) var nextMilestone: Int = 10
    @Published private(set) var timeoutDeadlineMs: Int64 = 0
    @Published private(set) var inActiveWar: Bool = false

    private let prefs: PrefsStore
    private let auth: AuthRepository
    private var task: Task<Void, Never>?

    init(prefs: PrefsStore) {
        self.prefs = prefs
        self.auth = AuthRepository(prefs: prefs)
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
              let a = await auth.ensureAuth() else {
            inActiveWar = false; chainCurrent = 0; timeoutDeadlineMs = 0; return
        }
        let wars = await WarboardAPI.fetchWars(
            baseUrl: prefs.baseUrl, factionId: a.factionId, jwt: a.token
        )
        guard let w = wars.first else {
            inActiveWar = false; chainCurrent = 0; timeoutDeadlineMs = 0; return
        }
        inActiveWar = true
        chainCurrent = w.chainCurrent ?? 0
        nextMilestone = nextChainMilestone(chainCurrent)
        let to = w.chainTimeout ?? 0
        timeoutDeadlineMs = to > 0 ? Int64(Date().timeIntervalSince1970 * 1000) + to * 1000 : 0
    }
}
