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
