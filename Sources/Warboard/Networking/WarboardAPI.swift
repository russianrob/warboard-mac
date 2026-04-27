import Foundation

/// Talks to the warboard server. Mirrors the Android `WarboardApi`
/// surface — same endpoints, same auth headers. v0.1 ships only the
/// pieces the War Room needs: auth, fetchWars, fetchPoll, callTarget.
enum WarboardAPI {
    // MARK: Auth

    struct AuthResult: Decodable {
        let token: String
        let player: Player
        struct Player: Decodable {
            let playerId: String
            let playerName: String
            let factionId: String
            let factionName: String
        }
    }

    /// POST /api/auth — exchange a Torn API key for a warboard JWT.
    static func authenticate(baseUrl: String, apiKey: String) async -> AuthResult? {
        guard let url = URL(string: baseUrl.trimmedSlash + "/api/auth") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["apiKey": apiKey])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(AuthResult.self, from: data)
        } catch {
            print("[WarboardAPI] auth failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Wars

    /// GET /api/faction/<fid>/war — list of active wars + targets.
    /// Same shape the Android client parses.
    static func fetchWars(baseUrl: String, factionId: String, jwt: String) async -> [WarSnapshot] {
        guard let url = URL(string: baseUrl.trimmedSlash + "/api/faction/\(factionId)/war") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let wars = root?["wars"] as? [[String: Any]] ?? []
            return wars.map(parseWar)
        } catch {
            print("[WarboardAPI] fetchWars failed: \(error.localizedDescription)")
            return []
        }
    }

    /// GET /api/poll — score + ETA + chain + ourFactionOnline.
    static func fetchPoll(baseUrl: String, jwt: String, warId: String) async -> WarPoll? {
        guard let encoded = warId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseUrl.trimmedSlash + "/api/poll?warId=\(encoded)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let scores = root["warScores"] as? [String: Any]
            let eta    = root["warEta"]    as? [String: Any]
            let target = root["warTarget"] as? [String: Any]
            let chain  = root["chainData"] as? [String: Any]
            let ourOnline = (root["ourFactionOnline"] as? [String: Any])?["count"] as? Int
                ?? (root["ourFactionOnline"] as? Int)
            return WarPoll(
                enemyFactionName: root["enemyFactionName"] as? String,
                myScore:    (scores?["myScore"]    as? Int) ?? 0,
                enemyScore: (scores?["enemyScore"] as? Int) ?? 0,
                targetScore: (target?["value"]        as? Int)
                    ?? (eta?["currentTarget"] as? Int)
                    ?? 0,
                etaEpochMs: (eta?["etaTimestamp"] as? Int64)
                    ?? (eta?["etaTimestamp"] as? Int).map(Int64.init),
                preWarPhase:  (eta?["preWarPhase"]  as? Bool) ?? false,
                preDropPhase: (eta?["preDropPhase"] as? Bool) ?? false,
                warEnded:     (root["warEnded"]     as? Bool) ?? false,
                ourFactionOnline: ourOnline,
                chainCurrent:  chain?["current"]  as? Int,
                chainCooldown: (chain?["cooldown"] as? Int64) ?? (chain?["cooldown"] as? Int).map(Int64.init),
                chainTimeout:  (chain?["timeout"]  as? Int64) ?? (chain?["timeout"]  as? Int).map(Int64.init)
            )
        } catch {
            print("[WarboardAPI] fetchPoll failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Scout report + heatmap (War sub-tabs)

    /// POST /api/war/<warId>/scout-report — server runs analyzeWarReport
    /// (plus FFScouter lookup) and returns the rich report payload.
    static func fetchScoutReport(baseUrl: String, jwt: String, warId: String) async -> ScoutReport? {
        guard let encoded = warId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseUrl.trimmedSlash + "/api/war/\(encoded)/scout-report") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        req.httpBody = "{}".data(using: .utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let r = root["report"] as? [String: Any] else { return nil }
            return parseScoutReport(r)
        } catch {
            return nil
        }
    }

    /// GET /api/heatmap?factionId=<fid> — day-of-week × hour-of-day
    /// activity matrix. Same endpoint the Android client uses.
    static func fetchHeatmap(baseUrl: String, jwt: String, factionId: String) async -> [Int: [Int: HeatmapCell]] {
        guard let encoded = factionId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseUrl.trimmedSlash + "/api/heatmap?factionId=\(encoded)") else { return [:] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let hm = root["heatmap"] as? [String: [String: [String: Any]]] ?? [:]
            var out: [Int: [Int: HeatmapCell]] = [:]
            for (dayStr, hours) in hm {
                guard let day = Int(dayStr) else { continue }
                var inner: [Int: HeatmapCell] = [:]
                for (hStr, c) in hours {
                    guard let h = Int(hStr) else { continue }
                    inner[h] = HeatmapCell(
                        total:        (c["total"]        as? Int) ?? 0,
                        samples:      (c["samples"]      as? Int) ?? 0,
                        membersTotal: (c["membersTotal"] as? Int) ?? 0
                    )
                }
                out[day] = inner
            }
            return out
        } catch { return [:] }
    }

    /// POST /api/me/bars — push our bars + cooldowns to warboard so
    /// the faction Members tab sees us as fresh. Same endpoint the
    /// userscript hits whenever it scrapes a Torn page.
    @discardableResult
    static func reportMyBars(
        baseUrl: String, jwt: String, snap: TornAPI.DashboardSnapshot
    ) async -> Bool {
        guard let url = URL(string: baseUrl.trimmedSlash + "/api/me/bars") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "bars": [
                "energy":  ["current": snap.energy.current, "maximum": snap.energy.maximum, "fulltime": snap.energy.fulltime],
                "nerve":   ["current": snap.nerve.current,  "maximum": snap.nerve.maximum,  "fulltime": snap.nerve.fulltime],
                "happy":   ["current": snap.happy.current,  "maximum": snap.happy.maximum,  "fulltime": snap.happy.fulltime],
                "life":    ["current": snap.life.current,   "maximum": snap.life.maximum,   "fulltime": snap.life.fulltime]
            ],
            "cooldowns": [
                "drug":    snap.drugSeconds,
                "medical": snap.medicalSeconds,
                "booster": snap.boosterSeconds
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    /// POST /api/call — call/uncall an enemy in the war room.
    static func callTarget(
        baseUrl: String, jwt: String, warId: String,
        action: String, targetId: String, targetName: String?
    ) async -> Bool {
        guard let url = URL(string: baseUrl.trimmedSlash + "/api/call") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "warId": warId, "action": action,
            "targetId": targetId, "targetName": targetName ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Parsing helpers

    private static func parseScoutReport(_ r: [String: Any]) -> ScoutReport {
        let ow      = r["warOverview"]  as? [String: Any]
        let ourOv   = ow?["our"]   as? [String: Any]
        let enemyOv = ow?["enemy"] as? [String: Any]
        let tiers   = r["statTiers"]  as? [String: Any]
        let safeHits = r["safeHits"]  as? [String: Any]
        let battle   = r["battlePlan"] as? [String: Any]
        let activity = r["activity"]  as? [String: Any]
        let topEnd   = r["topEnd"]    as? [String: Any]

        func tierCounts(_ side: [String: Any]?) -> TierCounts {
            TierCounts(
                s: (side?["S"] as? Int) ?? 0, a: (side?["A"] as? Int) ?? 0,
                b: (side?["B"] as? Int) ?? 0, c: (side?["C"] as? Int) ?? 0,
                d: (side?["D"] as? Int) ?? 0
            )
        }
        func parsePlayer(_ p: [String: Any]?) -> ReportPlayer? {
            guard let p = p else { return nil }
            return ReportPlayer(
                id: (p["id"] as? String) ?? "",
                name: (p["name"] as? String) ?? "",
                level: (p["level"] as? Int) ?? 0,
                statsFormatted: (p["statsFormatted"] as? String) ?? "",
                source: (p["source"] as? String) ?? ""
            )
        }
        func playerList(_ src: [String: Any]?, key: String) -> [ReportPlayer] {
            ((src?[key] as? [[String: Any]]) ?? []).compactMap(parsePlayer)
        }
        func parsePhase(name: String, targetsKey: String, ourKey: String? = nil) -> BattlePhase? {
            guard let phase = battle?[name] as? [String: Any] else { return nil }
            return BattlePhase(
                description: (phase["description"] as? String) ?? "",
                targets: playerList(phase, key: targetsKey),
                ourPlayers: ourKey.map { playerList(phase, key: $0) } ?? []
            )
        }

        func side(ov: [String: Any]?, t: [String: Any]?, act: [String: Any]?) -> ScoutSide {
            ScoutSide(
                factionName: (ov?["name"] as? String) ?? "",
                members:    (ov?["memberCount"] as? Int) ?? 0,
                respect:    (ov?["respect"]  as? Int) ?? 0,
                bestChain:  (ov?["bestChain"] as? Int) ?? 0,
                age:        (ov?["age"] as? Int) ?? 0,
                tiers: tierCounts(t),
                online:  (act?["online"]  as? Int) ?? 0,
                idle:    (act?["idle"]    as? Int) ?? 0,
                offline: (act?["offline"] as? Int) ?? 0,
                activeCombat: (act?["activeCombatRoster"] as? Int) ?? 0
            )
        }

        let matchups = ((topEnd?["matchups"] as? [[String: Any]]) ?? []).compactMap { mu -> Matchup? in
            Matchup(
                rank: (mu["rank"] as? Int) ?? 0,
                ours: parsePlayer(mu["ours"] as? [String: Any]),
                theirs: parsePlayer(mu["theirs"] as? [String: Any]),
                advantage: (mu["advantage"] as? String) ?? "even"
            )
        }
        let safe = SafeHits(
            thresholds: ((safeHits?["thresholds"] as? [[String: Any]]) ?? []).map {
                SafeHitThreshold(
                    label: ($0["label"] as? String) ?? "",
                    desc:  ($0["desc"]  as? String) ?? "",
                    ourCount:      ($0["ourCount"]      as? Int) ?? 0,
                    enemyFarmable: ($0["enemyFarmable"] as? Int) ?? 0
                )
            },
            ourCanHitPct:     (safeHits?["ourCanHitPct"]     as? Int) ?? 0,
            enemyFarmablePct: (safeHits?["enemyFarmablePct"] as? Int) ?? 0
        )
        let plan: BattlePlan? = battle.map { _ in
            BattlePlan(
                warPhase: (battle?["warPhase"] as? String) ?? "",
                opening:  parsePhase(name: "opening", targetsKey: "chainTargets", ourKey: "ourChainers"),
                midWar:   parsePhase(name: "midWar",  targetsKey: "permaTargets"),
                endgame:  parsePhase(name: "endgame", targetsKey: "enemyThreats", ourKey: "ourHitters"),
                ignore:   playerList(battle, key: "ignore"),
                keyPermaTargets: playerList(battle, key: "keyPermaTargets")
            )
        }
        let descObj = tiers?["descriptions"] as? [String: String] ?? [:]
        let tierDesc = TierDescriptions(
            s: descObj["S"] ?? "5B+ (elite)",
            a: descObj["A"] ?? "1B–5B (strong)",
            b: descObj["B"] ?? "250M–1B (solid)",
            c: descObj["C"] ?? "50M–250M (filler)",
            d: descObj["D"] ?? "<50M (non-threat)"
        )
        return ScoutReport(
            our: side(ov: ourOv, t: tiers?["our"] as? [String: Any], act: activity?["our"] as? [String: Any]),
            enemy: side(ov: enemyOv, t: tiers?["enemy"] as? [String: Any], act: activity?["enemy"] as? [String: Any]),
            matchups: matchups,
            safeHits: safe,
            battlePlan: plan,
            winProbability: (r["winProbability"] as? Int) ?? 0,
            winReasoning: (r["winReasoning"] as? [String]) ?? [],
            hasEstimates: (ow?["hasEstimates"] as? Bool) ?? false,
            tierDescriptions: tierDesc
        )
    }

    private static func parseWar(_ o: [String: Any]) -> WarSnapshot {
        let enemyStatuses = o["enemyStatuses"] as? [String: [String: Any]] ?? [:]
        let calls = o["calls"] as? [String: [String: Any]] ?? [:]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let targets = enemyStatuses.map { (id, s) -> EnemyTarget in
            let untilDouble = s["until"] as? Double ?? Double((s["until"] as? Int) ?? 0)
            let until = Int64(untilDouble)
            let caller = (calls[id]?["calledBy"]) as? [String: Any]
            return EnemyTarget(
                id: id,
                name: (s["name"] as? String) ?? "#\(id)",
                level: (s["level"] as? Int) ?? 0,
                status: (s["status"] as? String) ?? "",
                description: (s["description"] as? String) ?? "",
                untilSec: until,
                releaseAtMs: until > 0 ? now + until * 1000 : 0,
                activity: (s["activity"] as? String) ?? "offline",
                calledBy: caller?["name"] as? String,
                calledById: caller?["id"] as? String
            )
        }
        let scores = o["warScores"] as? [String: Any]
        let chain  = o["chainData"] as? [String: Any]
        return WarSnapshot(
            warId: (o["warId"] as? String) ?? "",
            enemyFactionId: (o["enemyFactionId"] as? String) ?? "",
            enemyFactionName: o["enemyFactionName"] as? String,
            myScore: (scores?["myScore"] as? Int) ?? 0,
            enemyScore: (scores?["enemyScore"] as? Int) ?? 0,
            warStart: (o["warStart"] as? Int64) ?? (o["warStart"] as? Int).map(Int64.init),
            warOrigTarget: o["warOrigTarget"] as? Int,
            currentTarget: o["currentTarget"] as? Int,
            chainCurrent:  chain?["current"]  as? Int,
            chainTimeout:  (chain?["timeout"]  as? Int64) ?? (chain?["timeout"]  as? Int).map(Int64.init),
            chainCooldown: (chain?["cooldown"] as? Int64) ?? (chain?["cooldown"] as? Int).map(Int64.init),
            targets: targets
        )
    }
}

private extension String {
    /// Strip a trailing slash so concatenation never yields `//api/...`.
    var trimmedSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
