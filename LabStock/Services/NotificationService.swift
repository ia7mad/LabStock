import Foundation
import UserNotifications

actor NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func reschedule(snapshots: [ItemSnapshot]) async {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }
        let storedWarningDays = UserDefaults.standard.integer(forKey: "expiryWarningDays")
        let warningDays = storedWarningDays > 0 ? storedWarningDays : 30
        let expired = snapshots.filter { $0.batches.contains { InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays) == .expired } }
        let expiring = snapshots.filter { snapshot in
            !expired.contains(where: { $0.id == snapshot.id }) && snapshot.batches.contains {
                InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays) == .expiringSoon
            }
        }
        let low = snapshots.filter { $0.totalQuantity <= $0.item.lowStockThreshold }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await schedule(id: identifiers[0], title: "Expired reagents", count: expired.count)
        await schedule(id: identifiers[1], title: "Reagents expiring soon", count: expiring.count)
        await schedule(id: identifiers[2], title: "Low stock", count: low.count)
    }

    private var identifiers: [String] { ["labstock.expired", "labstock.expiring", "labstock.low"] }

    private func schedule(id: String, title: String, count: Int) async {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "\(count) item\(count == 1 ? "" : "s") need attention in LabStock."
        content.sound = .default
        var components = DateComponents(); components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
