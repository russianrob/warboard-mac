import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var prefs: PrefsStore
    @EnvironmentObject private var updates: UpdateViewModel
    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var savedToast: String?

    var body: some View {
        Form {
            Section("Torn API key") {
                SecureField("32-character key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used for personal data + warboard authentication.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Warboard server") {
                TextField("Base URL", text: $baseUrl)
                    .textFieldStyle(.roundedBorder)
                Text("Default: https://tornwar.com")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let toast = savedToast {
                    Text(toast).foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Save") {
                    prefs.apiKey = apiKey
                    prefs.baseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    prefs.clearJwt()  // forces re-auth on next request
                    savedToast = "Saved — re-authenticating on next poll"
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            Section("Updates") {
                let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed: v\(current)")
                            .font(.subheadline)
                        if let avail = updates.available {
                            Text("Update available: \(avail.tagName)")
                                .foregroundStyle(.green)
                                .font(.caption.bold())
                        } else if let last = updates.lastCheckedAt {
                            Text("Up to date — last checked \(last.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Text("Update status pending…")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    Spacer()
                    if updates.available != nil {
                        Button("Download") { updates.openReleasePage() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(updates.checking ? "Checking…" : "Check now") {
                            Task { await updates.checkNow() }
                        }
                        .disabled(updates.checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: 520, alignment: .topLeading)
        .navigationTitle("Settings")
        .onAppear {
            apiKey = prefs.apiKey
            baseUrl = prefs.baseUrl
        }
    }
}
