import SwiftUI

/// NavigationSplitView with a sidebar (Status / War / Faction / Settings)
/// and a detail pane that swaps based on selection. Same four sections
/// the Android app's bottom-nav exposes.
struct ContentView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @State private var selection: SidebarItem? = .war

    var body: some View {
        NavigationSplitView {
            // NavigationLink(value:) is the value-based navigation
            // pattern NavigationSplitView expects on macOS 13+. The
            // earlier `.tag()` form rendered the row but didn't wire
            // up click → selection on the macOS sidebar.
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label(item.label, systemImage: item.icon)
                    }
                }
            }
            .navigationTitle("Warboard")
            .frame(minWidth: 180)
        } detail: {
            switch selection {
            case .status?:   DashboardView()
            case .war?:      WarRoomView()
            case .faction?:  FactionPlaceholderView()
            case .settings?: SettingsView()
            case nil:        Text("Select a section")
                .foregroundStyle(.secondary)
            }
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case status, war, faction, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .status:   return "Status"
        case .war:      return "War"
        case .faction:  return "Faction"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .status:   return "speedometer"
        case .war:      return "flame.fill"
        case .faction:  return "person.3.fill"
        case .settings: return "gear"
        }
    }
}

/// Stub for v0.1 — real Faction tab (Vault + Members) ships in v0.2.
struct FactionPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill").font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Faction tab coming in v0.2")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
