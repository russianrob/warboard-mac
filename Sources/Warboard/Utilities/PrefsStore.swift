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
    private static let kNotifyChain = "warboard.notify.chain"
    private static let kNotifyVault = "warboard.notify.vault"
    private static let kMenuBarChain = "warboard.menubar.chain"

    @Published var apiKey: String { didSet { defaults.set(apiKey, forKey: Self.kApiKey) } }
    @Published var baseUrl: String { didSet { defaults.set(baseUrl, forKey: Self.kBaseUrl) } }
    /// macOS notifications opt-ins. Default ON for chain (admins want
    /// to know when their chain is breaking) + vault (banker workflow).
    @Published var notifyChain: Bool { didSet { defaults.set(notifyChain, forKey: Self.kNotifyChain) } }
    @Published var notifyVault: Bool { didSet { defaults.set(notifyVault, forKey: Self.kNotifyVault) } }
    /// Whether the menu-bar status item shows the live chain count.
    @Published var menuBarChain: Bool { didSet { defaults.set(menuBarChain, forKey: Self.kMenuBarChain) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Self.kApiKey) ?? ""
        self.baseUrl = defaults.string(forKey: Self.kBaseUrl) ?? "https://tornwar.com"
        // Default ON for both notification categories on first run; user
        // can untoggle per category in Settings.
        self.notifyChain = defaults.object(forKey: Self.kNotifyChain) as? Bool ?? true
        self.notifyVault = defaults.object(forKey: Self.kNotifyVault) as? Bool ?? true
        self.menuBarChain = defaults.object(forKey: Self.kMenuBarChain) as? Bool ?? true
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
