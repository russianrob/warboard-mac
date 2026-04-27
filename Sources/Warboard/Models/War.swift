import Foundation

/// War snapshot from `/api/faction/<fid>/war`. Same field set the
/// Android `WarSnapshot` carries (minus chain rebase fields, added in
/// v0.2 alongside the in-app countdown).
struct WarSnapshot: Equatable {
    let warId: String
    let enemyFactionId: String
    let enemyFactionName: String?
    let myScore: Int
    let enemyScore: Int
    let warStart: Int64?
    let warOrigTarget: Int?
    let currentTarget: Int?
    let chainCurrent: Int?
    let chainTimeout: Int64?
    let chainCooldown: Int64?
    let targets: [EnemyTarget]
}

/// Single enemy in the war's target list. Mirrors the Android model.
struct EnemyTarget: Identifiable, Equatable {
    let id: String
    let name: String
    let level: Int
    /// "okay" | "hospital" | "jail" | "traveling" | "abroad" | …
    let status: String
    let description: String
    /// Server-supplied seconds remaining for status countdown.
    let untilSec: Int64
    /// Wall-clock deadline stamped at parse time (clientNow + until*1000).
    /// Lets the UI compute remaining as `deadline - now` for smooth
    /// per-second tick without drift between polls.
    let releaseAtMs: Int64
    let activity: String   // "online" | "idle" | "offline"
    let calledBy: String?
    let calledById: String?
}

/// Rich poll payload from `/api/poll`. v0.1 only consumes the fields
/// the War Room header needs; expand as later sub-tabs ship.
struct WarPoll: Equatable {
    let enemyFactionName: String?
    let myScore: Int
    let enemyScore: Int
    let targetScore: Int
    let etaEpochMs: Int64?
    let preWarPhase: Bool
    let preDropPhase: Bool
    let warEnded: Bool
    let ourFactionOnline: Int?
    let chainCurrent: Int?
    let chainCooldown: Int64?
    let chainTimeout: Int64?
}
