import Foundation
import Sparkle
import Combine

/// Thin SwiftUI-friendly wrapper around Sparkle's SPUStandardUpdaterController.
/// Sparkle reads SUFeedURL + SUPublicEDKey from Info.plist (set in
/// project.yml) so this controller just kicks the lifecycle.
///
/// First launch: Sparkle requests permission to auto-check; user can
/// flip the policy later from Settings via `setAutomaticallyChecks`.
@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    private let updaterController: SPUStandardUpdaterController

    /// Bound to the in-app Settings switch — when off Sparkle won't
    /// schedule background checks (manual "Check Now" still works).
    @Published var automaticChecks: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticChecks
        }
    }

    private init() {
        // startingUpdater = true makes Sparkle hook the app run loop
        // immediately on init — required for background checks to fire.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.automaticChecks = updaterController.updater.automaticallyChecksForUpdates
    }

    /// "Check for Updates…" menu action — opens Sparkle's UI flow:
    /// fetch appcast → if newer release found, show the standard
    /// release-notes window → user clicks Install → Sparkle downloads,
    /// verifies the Ed25519 signature, and replaces the running app.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
