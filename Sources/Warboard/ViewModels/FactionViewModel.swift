import Foundation
import Combine

/// Faction tab state holder. Polls vault requests + balance + member
/// bars every 30 s. Vault submit/cancel/claim trigger an immediate
/// re-poll so the UI reflects the change without a tick wait.
@MainActor
final class FactionViewModel: ObservableObject {
    @Published private(set) var vaultRequests: [VaultRequest] = []
    @Published private(set) var vaultBalance: Int64 = 0
    @Published private(set) var members: [MemberBars] = []
    @Published private(set) var loading = false
    @Published var statusMessage: String?

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
        guard let prefs = prefs, let auth = auth, !prefs.apiKey.isEmpty else { return }
        loading = true
        defer { loading = false }
        async let vrs = WarboardAPI.fetchVaultRequests(baseUrl: prefs.baseUrl, apiKey: prefs.apiKey)
        async let bal = WarboardAPI.fetchVaultBalance(baseUrl: prefs.baseUrl, apiKey: prefs.apiKey)
        let (v, b) = (await vrs, await bal)
        vaultRequests = v
        vaultBalance = b
        if let a = await auth.ensureAuth() {
            members = await WarboardAPI.fetchFactionMemberBars(baseUrl: prefs.baseUrl, jwt: a.token)
        }
    }

    func submit(amount: Int64, target: String) {
        guard let prefs = prefs, !prefs.apiKey.isEmpty else { return }
        Task {
            let id = await WarboardAPI.submitVaultRequest(
                baseUrl: prefs.baseUrl, apiKey: prefs.apiKey, amount: amount, target: target
            )
            statusMessage = id != nil
                ? "Requested $\(formatMoney(amount))"
                : "Couldn't submit — amount may exceed balance / cap"
            await tick()
        }
    }

    func cancel(_ id: String) {
        guard let prefs = prefs, !prefs.apiKey.isEmpty else { return }
        Task {
            let ok = await WarboardAPI.cancelVaultRequest(baseUrl: prefs.baseUrl, apiKey: prefs.apiKey, id: id)
            statusMessage = ok ? "Cancelled" : "Couldn't cancel"
            await tick()
        }
    }

    func claim(_ id: String) {
        guard let prefs = prefs, !prefs.apiKey.isEmpty else { return }
        Task {
            let ok = await WarboardAPI.claimVaultRequest(baseUrl: prefs.baseUrl, apiKey: prefs.apiKey, id: id)
            statusMessage = ok ? "Claimed — open Torn vault to send" : "Claim failed (already taken?)"
            await tick()
        }
    }
}

func formatMoney(_ n: Int64) -> String {
    if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1_000_000_000) }
    if n >= 1_000_000     { return String(format: "%.2fM", Double(n) / 1_000_000) }
    if n >= 1_000         { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}
