import SwiftUI

/// Top-level scene. Standalone WindowGroup is the primary surface
/// (mirrors the warboard-native Android app's bottom-nav). MenuBarExtra
/// is intentionally NOT included in v0.1 — adds it in a follow-up so
/// users get a glance/refresh status item alongside the main window.
@main
struct WarboardApp: App {
    @StateObject private var prefs = PrefsStore()
    @StateObject private var updates = UpdateViewModel()

    var body: some Scene {
        WindowGroup("Warboard") {
            ContentView()
                .environmentObject(prefs)
                .environmentObject(updates)
                .frame(minWidth: 720, minHeight: 600)
                .task {
                    // Auto-checks for updates on launch + every hour.
                    // Surfaced in Settings via a card; harmless when
                    // already up to date.
                    updates.start()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.checkNow() }
                }
            }
        }
    }
}
