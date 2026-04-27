import SwiftUI

/// MenuBarExtra label + popover content. Label is the chain count when
/// active (e.g. "⛓ 47/50") with color shifting amber/red as the timer
/// drops; popover gives quick refresh + reopen-window actions.
struct MenuBarChainLabel: View {
    @ObservedObject var ticker: ChainTickerViewModel
    @State private var nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    private let pulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if ticker.inActiveWar && ticker.chainCurrent > 0 {
                Text("⛓ \(ticker.chainCurrent)/\(ticker.nextMilestone)")
            } else {
                Image(systemName: "shield.lefthalf.filled")
            }
        }
        .onReceive(pulse) { _ in
            nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }
}

struct MenuBarChainPopover: View {
    @ObservedObject var ticker: ChainTickerViewModel
    @State private var nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    private let pulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ticker.inActiveWar {
                let remaining: Int = {
                    if ticker.timeoutDeadlineMs <= 0 { return 0 }
                    return max(0, Int((ticker.timeoutDeadlineMs - nowMs) / 1000))
                }()
                let color: Color = {
                    if ticker.chainCurrent == 0 { return .secondary }
                    if remaining <= 30 { return .red }
                    if remaining <= 60 { return .orange }
                    return .green
                }()
                HStack {
                    Text("Chain \(ticker.chainCurrent)/\(ticker.nextMilestone)")
                        .font(.headline).foregroundColor(color)
                    Spacer()
                    if remaining > 0 {
                        Text(formatDur(remaining)).foregroundColor(color).font(.subheadline.monospacedDigit())
                    } else if ticker.chainCurrent == 0 {
                        Text("no chain").foregroundStyle(.secondary).font(.caption)
                    }
                }
            } else {
                Text("No active war").foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Warboard") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Button("Refresh") { ticker.start() /* re-arms; tick fires */ }
            Divider()
            Button("Quit Warboard") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 220)
        .onReceive(pulse) { _ in
            nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        }
    }
}
