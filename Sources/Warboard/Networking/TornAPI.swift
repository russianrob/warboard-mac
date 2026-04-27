import Foundation

/// Direct calls to api.torn.com using the user's own API key. Mirrors
/// the Android `TornApi` — Status tab uses fetchDashboard; v0.3 will
/// add fetchFactionChain when we port the chain bar's direct path.
enum TornAPI {
    private static let base = "https://api.torn.com"
    private static let dashboardSelections = "basic,bars,cooldowns,profile,travel"

    struct Bar: Equatable {
        let current: Int
        let maximum: Int
        let fulltime: Int   // seconds until full
    }

    struct DashboardSnapshot: Equatable {
        let playerName: String
        let factionName: String?
        let energy: Bar
        let nerve: Bar
        let happy: Bar
        let life: Bar
        let drugSeconds: Int
        let medicalSeconds: Int
        let boosterSeconds: Int
        let travelDestination: String?
        let travelSecondsLeft: Int
        let statusState: String        // "Okay" | "Hospital" | "Jail" | "Traveling" | …
        let statusDescription: String
        let statusSecondsLeft: Int
        let fetchedAt: Date
        let error: String?
    }

    struct FactionChain: Equatable {
        let current: Int
        let max: Int
        let timeout: Int64        // seconds until break
        let cooldown: Int64       // seconds of post-break wait
        let modifier: Double      // respect multiplier at current count
    }

    /// `/v2/faction?selections=chain` — direct Torn fetch with the
    /// user's API key, same path the Android client uses for the chain
    /// bar. Bypasses warboard so the chain ticker works even when the
    /// warboard server is down or rate-limiting us.
    static func fetchFactionChain(apiKey: String) async -> FactionChain? {
        guard !apiKey.isEmpty,
              let url = URL(string: "\(base)/v2/faction?selections=chain&key=\(apiKey)")
        else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let c = root["chain"] as? [String: Any] else { return nil }
            return FactionChain(
                current:  (c["current"]  as? Int) ?? 0,
                max:      (c["max"]      as? Int) ?? 0,
                timeout:  (c["timeout"]  as? Int64) ?? Int64((c["timeout"]  as? Int) ?? 0),
                cooldown: (c["cooldown"] as? Int64) ?? Int64((c["cooldown"] as? Int) ?? 0),
                modifier: (c["modifier"] as? Double) ?? Double((c["modifier"] as? Int) ?? 1)
            )
        } catch { return nil }
    }

    /// `/v2/user?selections=basic,bars,cooldowns,profile,travel` →
    /// the everything-the-Status-tab-needs payload.
    static func fetchDashboard(apiKey: String) async -> DashboardSnapshot? {
        guard !apiKey.isEmpty,
              let url = URL(string: "\(base)/user/?selections=\(dashboardSelections)&key=\(apiKey)")
        else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let err = root["error"] as? [String: Any] {
                let msg = (err["error"] as? String) ?? "Torn API error"
                return DashboardSnapshot(
                    playerName: "", factionName: nil,
                    energy: Bar(current: 0, maximum: 100, fulltime: 0),
                    nerve:  Bar(current: 0, maximum: 100, fulltime: 0),
                    happy:  Bar(current: 0, maximum: 100, fulltime: 0),
                    life:   Bar(current: 0, maximum: 100, fulltime: 0),
                    drugSeconds: 0, medicalSeconds: 0, boosterSeconds: 0,
                    travelDestination: nil, travelSecondsLeft: 0,
                    statusState: "", statusDescription: "", statusSecondsLeft: 0,
                    fetchedAt: Date(), error: msg
                )
            }
            return parseDashboard(root)
        } catch {
            return nil
        }
    }

    private static func parseDashboard(_ root: [String: Any]) -> DashboardSnapshot {
        let bars = root["bars"] as? [String: Any] ?? [:]
        let cd = root["cooldowns"] as? [String: Any] ?? [:]
        let travel = root["travel"] as? [String: Any] ?? [:]
        let status = root["status"] as? [String: Any] ?? [:]

        let isTraveling = (travel["time_left"] as? Int).map { $0 > 0 } ?? false
        let dest = travel["destination"] as? String
        let timeLeft = (travel["time_left"] as? Int) ?? 0
        return DashboardSnapshot(
            playerName: (root["name"] as? String) ?? "",
            factionName: (root["faction"] as? [String: Any])?["faction_name"] as? String,
            energy: bar(bars["energy"]),
            nerve:  bar(bars["nerve"]),
            happy:  bar(bars["happy"]),
            life:   bar(bars["life"]),
            drugSeconds:    (cd["drug"]    as? Int) ?? 0,
            medicalSeconds: (cd["medical"] as? Int) ?? 0,
            boosterSeconds: (cd["booster"] as? Int) ?? 0,
            travelDestination: (isTraveling && dest != "Torn") ? dest : nil,
            travelSecondsLeft: timeLeft,
            statusState: (status["state"] as? String) ?? "Okay",
            statusDescription: (status["description"] as? String) ?? "",
            statusSecondsLeft: (status["until"] as? Int).map { max(0, $0 - Int(Date().timeIntervalSince1970)) } ?? 0,
            fetchedAt: Date(), error: nil
        )
    }

    private static func bar(_ raw: Any?) -> Bar {
        let o = (raw as? [String: Any]) ?? [:]
        return Bar(
            current:  (o["current"]  as? Int) ?? 0,
            maximum:  (o["maximum"]  as? Int) ?? 100,
            fulltime: (o["fulltime"] as? Int) ?? 0
        )
    }
}
