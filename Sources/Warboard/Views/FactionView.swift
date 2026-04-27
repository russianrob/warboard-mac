import SwiftUI
import AppKit

enum FactionSubTab: String, CaseIterable, Identifiable {
    case vault, members
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct FactionView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @StateObject private var vm = FactionViewModel()
    @State private var subTab: FactionSubTab = .vault

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $subTab) {
                ForEach(FactionSubTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.top, 8)

            switch subTab {
            case .vault:   VaultPanel(vm: vm)
            case .members: MembersPanel(vm: vm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Faction")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { vm.refresh() }) { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
            }
        }
        .onAppear { vm.bind(prefs: prefs); vm.start() }
        .onDisappear { vm.stop() }
        .alert(item: Binding(
            get: { vm.statusMessage.map { IdString(value: $0) } },
            set: { _ in vm.statusMessage = nil })
        ) { msg in
            Alert(title: Text(msg.value))
        }
    }
}

// IdString lives in WarRoomView.swift — single definition shared.

// MARK: Vault

private struct VaultPanel: View {
    @ObservedObject var vm: FactionViewModel
    @State private var amountText = ""
    @State private var targetOnline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Submit form
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "banknote.fill").foregroundColor(.green)
                    Text("Vault: $\(formatMoney(vm.vaultBalance))")
                        .font(.subheadline.bold())
                    Spacer()
                }
                HStack {
                    TextField("Amount", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                    Button("Max") {
                        amountText = "\(vm.vaultBalance)"
                    }.buttonStyle(.bordered)
                }
                HStack {
                    Toggle("Online only", isOn: $targetOnline)
                    Spacer()
                    Button("Request") {
                        if let amt = Int64(amountText), amt > 0 {
                            vm.submit(amount: amt, target: targetOnline ? "online" : "both")
                            amountText = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(Int64(amountText).map { $0 <= 0 } ?? true)
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            // Pending list
            if vm.vaultRequests.isEmpty {
                Text("No pending vault requests.")
                    .foregroundStyle(.secondary).font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                List {
                    ForEach(vm.vaultRequests) { r in
                        VaultRow(request: r,
                                 onClaim: { vm.claim(r.id) },
                                 onCancel: { vm.cancel(r.id) })
                    }
                }
                .listStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
    }
}

private struct VaultRow: View {
    let request: VaultRequest
    let onClaim: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let ageMin = max(0, Int((Date().timeIntervalSince1970 * 1000 - Double(request.createdAt)) / 60_000))
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Button(request.requesterName) {
                    if let url = URL(string: "https://www.torn.com/profiles.php?XID=\(request.requesterId)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Text("$\(formatMoney(request.amount))")
                        .foregroundColor(.green).font(.caption.bold())
                    Text("\(ageMin)m ago").foregroundStyle(.secondary).font(.caption2)
                    if request.target == "online" {
                        Text("online only").foregroundStyle(.secondary).font(.caption2)
                    }
                }
            }
            Spacer()
            Button("Send") { onClaim() }.buttonStyle(.borderedProminent).controlSize(.small)
            Button("✕") { onCancel() }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: Members

private struct MembersPanel: View {
    @ObservedObject var vm: FactionViewModel
    var body: some View {
        if vm.members.isEmpty {
            Text("No member-bars data yet — wait a poll cycle.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let now = Date().timeIntervalSince1970 * 1000
            List(vm.members) { m in
                MemberRow(member: m, nowMs: Int64(now))
            }
            .listStyle(.plain)
        }
    }
}

private struct MemberRow: View {
    let member: MemberBars
    let nowMs: Int64

    var body: some View {
        let ageMin = max(0, Int((nowMs - member.updatedAt) / 60_000))
        let ageColor: Color = ageMin < 5 ? .green : ageMin < 30 ? .yellow : .secondary
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(member.playerName) {
                    if let url = URL(string: "https://www.torn.com/profiles.php?XID=\(member.playerId)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline.bold())
                Spacer()
                Text(ageMin < 1 ? "now" : "\(ageMin)m")
                    .foregroundColor(ageColor).font(.caption2)
            }
            BarStripe(label: "E", current: member.energy[0], max: member.energy[1], color: .cyan)
            BarStripe(label: "N", current: member.nerve[0],  max: member.nerve[1],  color: .red)
            BarStripe(label: "H", current: member.happy[0],  max: member.happy[1],  color: .yellow)
            if member.life[0] < member.life[1] {
                BarStripe(label: "L", current: member.life[0], max: member.life[1], color: .green)
            }
            // Cooldown chips inline
            let cdLabels: [String] = {
                var out: [String] = []
                if member.drugSec > 0    { out.append("Drug \(formatDur(Int(member.drugSec)))") }
                if member.medicalSec > 0 { out.append("Med \(formatDur(Int(member.medicalSec)))") }
                if member.boosterSec > 0 { out.append("Boost \(formatDur(Int(member.boosterSec)))") }
                return out
            }()
            if !cdLabels.isEmpty {
                Text(cdLabels.joined(separator: " · "))
                    .foregroundStyle(.secondary).font(.caption2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BarStripe: View {
    let label: String; let current: Int; let max: Int; let color: Color
    var body: some View {
        let pct = max > 0 ? Double(current) / Double(max) : 0
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).font(.caption2.bold()).frame(width: 12)
            ProgressView(value: pct).tint(color)
            Text("\(current)/\(max)").foregroundStyle(.secondary).font(.caption2).frame(width: 64, alignment: .trailing)
        }
    }
}
