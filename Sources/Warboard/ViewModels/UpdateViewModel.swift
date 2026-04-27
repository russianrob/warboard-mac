import Foundation
import Combine

/// Wraps UpdateManager.shared in an ObservableObject so SwiftUI views
/// (Settings + a future toolbar badge) can react to "update found".
/// Checks once on app launch + once per hour while the app stays open.
@MainActor
final class UpdateViewModel: ObservableObject {
    @Published private(set) var available: GitHubRelease?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var checking = false

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)  // 1h
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
    }

    func checkNow() async {
        checking = true
        defer { checking = false; lastCheckedAt = Date() }
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        if let release = await UpdateManager.shared.checkForUpdates(currentVersion: current) {
            available = release
        }
    }

    /// Open the release page in the user's browser so they can download
    /// the DMG. v0.2 will swap this for a Sparkle-style in-app install.
    func openReleasePage() {
        guard let release = available, let url = URL(string: release.htmlUrl) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif
