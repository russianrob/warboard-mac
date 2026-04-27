import SwiftUI

/// v0.1 stub. v0.2 will mirror the Android Status tab — bars, cooldowns,
/// travel, status banner — using TornAPI.fetchDashboard.
struct DashboardView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "speedometer").font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Status tab coming in v0.2")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Status")
    }
}
