import Foundation

/// Cached warboard JWT + identity. Mirrors the Android CachedAuth.
struct CachedAuth: Equatable {
    let token: String
    let factionId: String
    let factionName: String
    let playerId: String
}
