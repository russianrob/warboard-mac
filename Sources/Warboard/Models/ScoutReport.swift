import Foundation

/// Activity heatmap cell — average active = total / samples.
struct HeatmapCell: Equatable {
    let total: Int
    let samples: Int
    let membersTotal: Int
}

struct TierCounts: Equatable {
    let s: Int; let a: Int; let b: Int; let c: Int; let d: Int
}

struct TierDescriptions: Equatable {
    let s: String; let a: String; let b: String; let c: String; let d: String
}

struct ScoutSide: Equatable {
    let factionName: String
    let members: Int
    let respect: Int
    let bestChain: Int
    let age: Int            // days since founded
    let tiers: TierCounts
    let online: Int
    let idle: Int
    let offline: Int
    let activeCombat: Int   // members currently combat-ready
}

struct ReportPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let level: Int
    let statsFormatted: String
    let source: String      // "ffs", "bsp", "level"
}

struct Matchup: Identifiable, Equatable {
    var id: Int { rank }
    let rank: Int
    let ours: ReportPlayer?
    let theirs: ReportPlayer?
    let advantage: String   // "ours", "theirs", "even"
}

struct SafeHitThreshold: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let desc: String
    let ourCount: Int
    let enemyFarmable: Int
}

struct SafeHits: Equatable {
    let thresholds: [SafeHitThreshold]
    let ourCanHitPct: Int
    let enemyFarmablePct: Int
}

struct BattlePhase: Equatable {
    let description: String
    let targets: [ReportPlayer]
    let ourPlayers: [ReportPlayer]
}

struct BattlePlan: Equatable {
    let warPhase: String         // "early" | "mid" | "late"
    let opening: BattlePhase?
    let midWar: BattlePhase?
    let endgame: BattlePhase?
    let ignore: [ReportPlayer]
    let keyPermaTargets: [ReportPlayer]
}

struct ScoutReport: Equatable {
    let our: ScoutSide
    let enemy: ScoutSide
    let matchups: [Matchup]
    let safeHits: SafeHits
    let battlePlan: BattlePlan?
    let winProbability: Int
    let winReasoning: [String]
    let hasEstimates: Bool
    let tierDescriptions: TierDescriptions
}
