import Foundation
import UserNotifications
import AppKit

/// Thin wrapper around UNUserNotificationCenter. First call to `fire`
/// triggers the macOS permission prompt; subsequent calls just post.
/// Notifications are silent on the screen if the user denied — no UI
/// fallback in v0.4.
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private var requested = false

    /// Notification categories the app can post. Maps to a Settings
    /// toggle so users opt out per category instead of all-or-nothing.
    enum Category: String {
        case chainBreaking = "chain_breaking"     // ≤ 60 s
        case chainPanic    = "chain_panic"        // ≤ 30 s
        case vaultRequest  = "vault_request"
        case shoutIncoming = "shout_incoming"     // reserved for v0.5
    }

    /// Posts a notification. Title is bolded; body is the line below.
    /// `id` should be stable per logical event (e.g. the vault-request
    /// id) so we replace rather than spam if the same event fires twice.
    func fire(title: String, body: String, category: Category, id: String) {
        ensurePermissionThenPost { [weak self] granted in
            guard let self = self, granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = category == .chainPanic ? .defaultCritical : .default
            content.categoryIdentifier = category.rawValue
            let req = UNNotificationRequest(
                identifier: "\(category.rawValue).\(id)",
                content: content,
                trigger: nil
            )
            self.center.add(req)
        }
    }

    private func ensurePermissionThenPost(_ then: @escaping (Bool) -> Void) {
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .authorized, .provisional:
                then(true)
            case .notDetermined:
                if !self.requested {
                    self.requested = true
                    self.center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                        then(ok)
                    }
                } else { then(false) }
            default:
                then(false)
            }
        }
    }

    /// Set / clear the Dock icon badge. nil clears it. macOS uses the
    /// badge count for visual unread indicators on the running app.
    @MainActor
    func setDockBadge(_ count: Int?) {
        let label: String
        if let c = count, c > 0 { label = "\(c)" } else { label = "" }
        NSApplication.shared.dockTile.badgeLabel = label.isEmpty ? nil : label
    }
}
