import SwiftUI

/// Top-level scene. Standalone WindowGroup is the primary surface
/// (mirrors the warboard-native Android app's bottom-nav). MenuBarExtra
/// is intentionally NOT included in v0.1 — adds it in a follow-up so
/// users get a glance/refresh status item alongside the main window.
@main
struct WarboardApp: App {
    @StateObject private var prefs = PrefsStore()

    var body: some Scene {
        WindowGroup("Warboard") {
            ContentView()
                .environmentObject(prefs)
                .frame(minWidth: 720, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            // Hide the default "New Window" menu — single-window app.
            CommandGroup(replacing: .newItem) { }
        }
    }
}
