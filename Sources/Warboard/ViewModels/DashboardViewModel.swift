import Foundation
import Combine

/// Status tab state holder. Polls /v2/user every 30 s while the tab
/// is on screen and pushes our bars to warboard so the rest of the
/// faction sees us as fresh in their Members tab.
@MainActor
final class DashboardViewModel: ObservableObject {
    enum State: Equatable {
        case noKey, loading, ready(TornAPI.DashboardSnapshot), error(String)
    }

    @Published private(set) var state: State = .loading

    private var prefs: PrefsStore?
    private var auth: AuthRepository?
    private var task: Task<Void, Never>?

    func bind(prefs: PrefsStore) {
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
    func refresh() { Task { await tick() } }

    private func tick() async {
        guard let prefs = prefs else { return }
        if prefs.apiKey.isEmpty { state = .noKey; return }
        guard let snap = await TornAPI.fetchDashboard(apiKey: prefs.apiKey) else {
            state = .error("Couldn't reach Torn API"); return
        }
        if let err = snap.error { state = .error(err); return }
        state = .ready(snap)
        // Self-report bars to warboard so faction Members tab sees us
        // fresh — same path the userscript fires on every page load.
        if let auth = auth, let a = await auth.ensureAuth() {
            await WarboardAPI.reportMyBars(baseUrl: prefs.baseUrl, jwt: a.token, snap: snap)
        }
    }
}
