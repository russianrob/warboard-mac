import Foundation

/// Latest release metadata from the GitHub API. Mirrors the slimmed-
/// down struct MacTorn uses — only the fields we actually surface in
/// the Settings tab + the auto-prompt.
struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

/// Polls the warboard-mac GitHub repo for the most recent release. The
/// build-dmg.yml workflow attaches a DMG to every tagged release, so
/// `htmlUrl` lands on a page where the user can grab the new build.
///
/// To wire signing + auto-install (Sparkle-style), swap this out for
/// SUUpdater later — keeping it dependency-free for v0.1.
final class UpdateManager {
    static let shared = UpdateManager()

    private let owner = "russianrob"
    private let repo  = "warboard-mac"

    /// Returns a release strictly newer than `current`, or nil when we
    /// can't fetch / are already up to date. Fails silently — settings
    /// just won't show an update prompt.
    func checkForUpdates(currentVersion: String) async -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            // Strip a leading "v" from "v0.1.0" before comparing.
            let candidate = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            if isVersion(candidate, greaterThan: currentVersion) {
                return release
            }
        } catch {
            // No connectivity, rate-limit, schema change — degrade
            // silently. Update check is a nice-to-have, never required.
        }
        return nil
    }

    /// Lexicographic semver compare — splits on dots, pads shorter side
    /// with zeros, returns true when `new` is strictly greater.
    private func isVersion(_ new: String, greaterThan current: String) -> Bool {
        let n = new.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let len = max(n.count, c.count)
        for i in 0..<len {
            let a = i < n.count ? n[i] : 0
            let b = i < c.count ? c[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}
