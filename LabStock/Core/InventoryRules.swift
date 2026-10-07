import Foundation

enum ExpiryStatus: Equatable {
    case expired, expiringSoon, normal, unknown
}

enum InventoryRules {
    static func expiryStatus(for date: Date?, warningDays: Int, now: Date = .now, calendar: Calendar = .current) -> ExpiryStatus {
        guard let date else { return .unknown }
        let today = calendar.startOfDay(for: now)
        let expiry = calendar.startOfDay(for: date)
        if expiry < today { return .expired }
        let warning = calendar.date(byAdding: .day, value: max(0, warningDays), to: today) ?? today
        return expiry <= warning ? .expiringSoon : .normal
    }

    static func validate(delta: Int, current: Int, allowNegative: Bool = false) -> Bool {
        delta != 0 && (allowNegative || current + delta >= 0)
    }

    static func preferredFEFOBatch(from batches: [Batch], now: Date = .now, calendar: Calendar = .current) -> Batch? {
        let today = calendar.startOfDay(for: now)
        let available = batches.filter { $0.currentQuantity > 0 }
        let valid = available.filter { batch in
            guard let expiry = batch.expiryDate else { return false }
            return calendar.startOfDay(for: expiry) >= today
        }
        return valid.sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }.first
            ?? available.first(where: { $0.expiryDate == nil })
            ?? available.sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }.first
    }

    static func difference(expected: Int, counted: Int) -> Int { counted - expected }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
