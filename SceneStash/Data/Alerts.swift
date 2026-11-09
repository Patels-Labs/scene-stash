import UIKit
import UserNotifications

/// Premiere alerts, an All-Access extra. At most two kinds, never more: one at six on the evening a new episode
/// of a show you're watching lands, and one three days before a season premiere of anything in your stash.
enum Alerts {
    static let category = "episode"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "alerts") }
        set { UserDefaults.standard.set(newValue, forKey: "alerts") }
    }

    /// Asks for permission the first time; returns whether alerts are on.
    static func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        enabled = granted
        return granted
    }

    static func disable() {
        enabled = false
        clear()
    }

    static func registerCategory() {
        let open = UNNotificationAction(identifier: "open", title: "Open Tonight", options: [.foreground])
        let later = UNNotificationAction(identifier: "later", title: "Not tonight")
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: category, actions: [open, later], intentIdentifiers: [])])
    }

    /// Replaces every scheduled alert from what's tracked now. Called whenever Tonight refreshes its show details.
    static func reschedule(_ details: [TitleDetail]) {
        clear()
        guard enabled, Pass.shared.isUnlocked else { return }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        for detail in details {
            guard let next = detail.nextEpisodeToAir, let air = next.airDate.flatMap(DateText.date) else { continue }
            let status = Store.shared.tracked(detail.id, .tv)?.status
            if status == .watching, let evening = cal.date(bySettingHour: 18, minute: 0, second: 0, of: air), evening > .now {
                add(center, id: "\(detail.id)-night", at: evening,
                    title: "On tonight: \(detail.name)",
                    body: "S\(next.seasonNumber) E\(next.episodeNumber) is out. It'll be on your programme.")
            }
            if next.episodeNumber == 1, status != nil,
               let early = cal.date(byAdding: .day, value: -3, to: air).flatMap({ cal.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }), early > .now {
                add(center, id: "\(detail.id)-premiere", at: early,
                    title: "\(detail.name) returns \(air.formatted(.dateTime.weekday(.wide)))",
                    body: "Season \(next.seasonNumber) premieres in 3 days.")
            }
        }
    }

    private static func add(_ center: UNUserNotificationCenter, id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    /// These alerts are the only notifications the app schedules, so clearing means clearing everything pending.
    private static func clear() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
