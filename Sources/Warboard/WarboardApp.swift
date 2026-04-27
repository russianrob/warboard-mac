import SwiftUI

/// Top-level scene. Standalone WindowGroup is the primary surface
/// (mirrors the warboard-native Android app's bottom-nav). MenuBarExtra
/// is intentionally NOT included in v0.1 — adds it in a follow-up so
/// users get a glance/refresh status item alongside the main window.
@main
struct WarboardApp: App {
    @StateObject private var prefs = PrefsStore()
    @StateObject private var updates = UpdateViewModel()
    /// Menu-bar status item runs its own lightweight chain ticker —
    /// independent of the main War Room view's polling loop so the
    /// label stays live even when the window is closed/hidden.
    @StateObject private var menuChain: ChainTickerViewModel

    init() {
        let p = PrefsStore()
        _prefs = StateObject(wrappedValue: p)
        _menuChain = StateObject(wrappedValue: ChainTickerViewModel(prefs: p))
    }

    var body: some Scene {
        WindowGroup("Warboard") {
            ContentView()
                .environmentObject(prefs)
                .environmentObject(updates)
                .frame(minWidth: 720, minHeight: 600)
                .task {
                    updates.start()
                    menuChain.start()
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

        // Live chain count + quick popover. User can hide it via
        // Settings → Menu bar toggle (sets MenuBarExtra isInserted).
        MenuBarExtra(isInserted: $prefs.menuBarChain) {
            MenuBarChainPopover(ticker: menuChain)
        } label: {
            MenuBarChainLabel(ticker: menuChain)
        }
        .menuBarExtraStyle(.window)
    }
}
