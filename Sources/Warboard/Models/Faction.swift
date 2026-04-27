import Foundation

/// Pending vault request from /api/oc/vault-requests.
struct VaultRequest: Identifiable, Equatable {
    let id: String
    let requesterId: String
    let requesterName: String
    let amount: Int64
    let target: String      // "online" | "both"
    let createdAt: Int64    // ms
}

/// Faction member bar snapshot from /api/faction/bars.
struct MemberBars: Identifiable, Equatable {
    var id: String { playerId }
    let playerId: String
    let playerName: String
    /// Each bar is [current, maximum] for compact rendering.
    let energy: [Int]
    let nerve: [Int]
    let happy: [Int]
    let life: [Int]
    let drugSec: Int64
    let medicalSec: Int64
    let boosterSec: Int64
    let updatedAt: Int64    // ms
}

/// FFScouter player-flights estimate per traveling enemy.
struct TravelInfo: Equatable {
    let landingAt: Int64    // unix seconds
    let destination: String
    let returning: Bool
    let method: String
}
