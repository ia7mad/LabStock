import XCTest
@testable import LabStock

final class InventoryRulesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testExpiryStatuses() {
        let now = date(2026, 10, 7)
        XCTAssertEqual(InventoryRules.expiryStatus(for: date(2026, 10, 6), warningDays: 30, now: now, calendar: calendar), .expired)
        XCTAssertEqual(InventoryRules.expiryStatus(for: date(2026, 11, 6), warningDays: 30, now: now, calendar: calendar), .expiringSoon)
        XCTAssertEqual(InventoryRules.expiryStatus(for: date(2026, 11, 7), warningDays: 30, now: now, calendar: calendar), .normal)
        XCTAssertEqual(InventoryRules.expiryStatus(for: nil, warningDays: 30, now: now, calendar: calendar), .unknown)
    }

    func testQuantityValidation() {
        XCTAssertTrue(InventoryRules.validate(delta: 2, current: 1))
        XCTAssertTrue(InventoryRules.validate(delta: -1, current: 1))
        XCTAssertFalse(InventoryRules.validate(delta: -2, current: 1))
        XCTAssertFalse(InventoryRules.validate(delta: 0, current: 1))
        XCTAssertTrue(InventoryRules.validate(delta: -2, current: 1, allowNegative: true))
    }

    func testFEFOSelectsNearestNonExpiredAvailableBatch() {
        let itemID = UUID()
        let userID = UUID()
        let old = Batch(id: UUID(), itemId: itemID, lotNumber: "OLD", expiryDate: date(2026, 10, 1), currentQuantity: 5, createdAt: date(2026, 1, 1), createdBy: userID)
        let near = Batch(id: UUID(), itemId: itemID, lotNumber: "NEAR", expiryDate: date(2026, 10, 20), currentQuantity: 2, createdAt: date(2026, 1, 1), createdBy: userID)
        let far = Batch(id: UUID(), itemId: itemID, lotNumber: "FAR", expiryDate: date(2027, 1, 1), currentQuantity: 8, createdAt: date(2026, 1, 1), createdBy: userID)
        XCTAssertEqual(InventoryRules.preferredFEFOBatch(from: [far, old, near], now: date(2026, 10, 7), calendar: calendar)?.id, near.id)
    }

    func testInventoryDifference() {
        XCTAssertEqual(InventoryRules.difference(expected: 8, counted: 5), -3)
        XCTAssertEqual(InventoryRules.difference(expected: 4, counted: 7), 3)
    }
}

