import Foundation
import Combine

/// UserDefaults-backed prefs. Mirrors the Android `Prefs` DataStore so
/// the same conceptual fields exist on both clients. v0.1 stores the
/// Torn API key in plain UserDefaults; we'll move to Keychain in v0.2.
final class PrefsStore: ObservableObject {
    private let defaults: UserDefaults
    private static let kApiKey = "warboard.apiKey"
    private static let kBaseUrl = "warboard.baseUrl"
    private static let kJwt = "warboard.jwt"
    private static let kFactionId = "warboard.factionId"
    private static let kFactionName = "warboard.factionName"
    private static let kPlayerId = "warboard.playerId"

    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: Self.kApiKey) } }
    @Published var baseUrl: String { didSet { defaults.set(baseUrl, forKey: Self.kBaseUrl) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Self.kApiKey) ?? ""
        self.baseUrl = defaults.string(forKey: Self.kBaseUrl) ?? "https://tornwar.com"
    }

    // JWT cache helpers — accessed by AuthRepository, not the UI.
    func cachedJwt() -> CachedAuth? {
        guard let token = defaults.string(forKey: Self.kJwt), !token.isEmpty else { return nil }
        return CachedAuth(
            token: token,
            factionId: defaults.string(forKey: Self.kFactionId) ?? "",
            factionName: defaults.string(forKey: Self.kFactionName) ?? "",
            playerId: defaults.string(forKey: Self.kPlayerId) ?? ""
        )
    }

    func storeJwt(_ auth: CachedAuth) {
        defaults.set(auth.token, forKey: Self.kJwt)
        defaults.set(auth.factionId, forKey: Self.kFactionId)
        defaults.set(auth.factionName, forKey: Self.kFactionName)
        defaults.set(auth.playerId, forKey: Self.kPlayerId)
    }

    func clearJwt() {
        for key in [Self.kJwt, Self.kFactionId, Self.kFactionName, Self.kPlayerId] {
            defaults.removeObject(forKey: key)
        }
    }
}
