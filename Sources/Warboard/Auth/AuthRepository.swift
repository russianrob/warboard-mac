import Foundation

/// Lazy JWT cache. Mirrors the Android AuthRepository — cached token is
/// reused across launches; we only re-auth when it's missing or a 401
/// invalidates it.
@MainActor
final class AuthRepository {
    private let prefs: PrefsStore
    init(prefs: PrefsStore) { self.prefs = prefs }

    func ensureAuth() async -> CachedAuth? {
        if prefs.apiKey.isEmpty { return nil }
        if let cached = prefs.cachedJwt(), !cached.token.isEmpty { return cached }

        guard let result = await WarboardAPI.authenticate(
            baseUrl: prefs.baseUrl, apiKey: prefs.apiKey
        ) else { return nil }
        let auth = CachedAuth(
            token: result.token,
            factionId: result.player.factionId,
            factionName: result.player.factionName,
            playerId: result.player.playerId
        )
        prefs.storeJwt(auth)
        return auth
    }

    func invalidate() { prefs.clearJwt() }
}
