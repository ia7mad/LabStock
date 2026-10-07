import XCTest
@testable import LabStock

final class Phase2Tests: XCTestCase {
    private let userID = UUID()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func item(name: String, reference: String? = nil, manufacturer: String? = nil, threshold: Int = 2, unit: String = "kit", groupID: UUID? = nil) -> StockItem {
        StockItem(
            id: UUID(),
            groupId: groupID,
            name: name,
            manufacturer: manufacturer,
            referenceNumber: reference,
            notes: nil,
            lowStockThreshold: threshold,
            unitName: unit,
            createdAt: date(2026, 1, 1),
            createdBy: userID
        )
    }

    private func batch(itemID: UUID, lot: String?, expiry: Date?, quantity: Int) -> Batch {
        Batch(
            id: UUID(),
            itemId: itemID,
            lotNumber: lot,
            expiryDate: expiry,
            currentQuantity: quantity,
            createdAt: date(2026, 1, 1),
            createdBy: userID
        )
    }

    private func snapshot(_ item: StockItem, _ batches: [Batch]) -> ItemSnapshot {
        ItemSnapshot(item: item, batches: batches)
    }

    // MARK: Stock correction

    func testAdjustmentDeltaAndValidation() {
        XCTAssertEqual(InventoryRules.adjustmentDelta(current: 10, actual: 8), -2)
        XCTAssertEqual(InventoryRules.adjustmentDelta(current: 3, actual: 9), 6)
        XCTAssertEqual(InventoryRules.adjustmentDelta(current: 5, actual: 5), 0)
        XCTAssertTrue(InventoryRules.isValidAdjustment(delta: -2))
        XCTAssertFalse(InventoryRules.isValidAdjustment(delta: 0))
    }

    // MARK: Batch edit safety

    func testBatchIdentityDetectsDuplicateLots() {
        let expiry = date(2027, 9, 22)
        XCTAssertEqual(
            InventoryRules.batchIdentity(lotNumber: "2850", expiryDate: expiry, calendar: calendar),
            InventoryRules.batchIdentity(lotNumber: "lot 2850", expiryDate: expiry, calendar: calendar)
        )
        XCTAssertNotEqual(
            InventoryRules.batchIdentity(lotNumber: "2850", expiryDate: expiry, calendar: calendar),
            InventoryRules.batchIdentity(lotNumber: "2851", expiryDate: expiry, calendar: calendar)
        )
        XCTAssertNotEqual(
            InventoryRules.batchIdentity(lotNumber: "2850", expiryDate: expiry, calendar: calendar),
            InventoryRules.batchIdentity(lotNumber: "2850", expiryDate: date(2028, 1, 1), calendar: calendar)
        )
        XCTAssertEqual(
            InventoryRules.batchIdentity(lotNumber: nil, expiryDate: nil, calendar: calendar),
            InventoryRules.batchIdentity(lotNumber: "   ", expiryDate: nil, calendar: calendar)
        )
    }

    // MARK: Export

    func testInventoryCSVFormattingAndEscaping() {
        let groupID = UUID()
        let group = InventoryGroup(id: groupID, name: "AU5800", createdAt: date(2026, 1, 1), createdBy: userID)
        let reagent = item(name: "ISE \"Mid\" Standard, 300mL", reference: "66319", manufacturer: "Roche", groupID: groupID)
        let rows = InventoryExport.rows(
            snapshots: [snapshot(reagent, [batch(itemID: reagent.id, lot: "2850", expiry: date(2027, 9, 22), quantity: 3)])],
            groups: [group],
            warningDays: 30,
            now: date(2026, 10, 7),
            calendar: calendar
        )
        let csv = InventoryExport.inventoryCSV(rows: rows, summary: InventoryExport.summary(forRows: rows), generatedAt: date(2026, 10, 7))

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("Group,Item Name,Manufacturer,REF,LOT,Expiry,Quantity,Unit,Status"))
        XCTAssertTrue(csv.contains("\"ISE \"\"Mid\"\" Standard, 300mL\",Roche,66319,2850,2027-09-22,3,kit,NORMAL"))
        XCTAssertTrue(csv.contains("\r\n"))
        XCTAssertTrue(csv.contains("Total Quantity,3"))
    }

    func testCSVHasOneRowPerBatchAndSummary() {
        let reagent = item(name: "ISE Mid Standard", reference: "66319", threshold: 2)
        let first = batch(itemID: reagent.id, lot: "2850", expiry: date(2027, 9, 22), quantity: 3)
        let second = batch(itemID: reagent.id, lot: "3010", expiry: date(2028, 1, 15), quantity: 5)
        let rows = InventoryExport.rows(
            snapshots: [snapshot(reagent, [first, second])],
            groups: [],
            warningDays: 30,
            now: date(2026, 10, 7),
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.lot), ["2850", "3010"])
        XCTAssertEqual(rows.map(\.group), ["Ungrouped", "Ungrouped"])

        let summary = InventoryExport.summary(forRows: rows)
        XCTAssertEqual(summary.totalItems, 1)
        XCTAssertEqual(summary.totalBatches, 2)
        XCTAssertEqual(summary.totalQuantity, 8)
    }

    func testCSVFieldEscaping() {
        XCTAssertEqual(InventoryExport.csvField("plain"), "plain")
        XCTAssertEqual(InventoryExport.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(InventoryExport.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(InventoryExport.csvField("line\nbreak"), "\"line\nbreak\"")
    }

    func testExportStatusValues() {
        let normal = item(name: "Normal", threshold: 1)
        let low = item(name: "Low", threshold: 5)
        XCTAssertEqual(snapshot(normal, [batch(itemID: normal.id, lot: "A", expiry: date(2028, 1, 1), quantity: 4)]).status(warningDays: 30, now: date(2026, 10, 7), calendar: calendar), .normal)
        XCTAssertEqual(snapshot(low, [batch(itemID: low.id, lot: "A", expiry: date(2028, 1, 1), quantity: 2)]).status(warningDays: 30, now: date(2026, 10, 7), calendar: calendar), .lowStock)
        XCTAssertEqual(snapshot(normal, [batch(itemID: normal.id, lot: "A", expiry: date(2026, 10, 20), quantity: 4)]).status(warningDays: 30, now: date(2026, 10, 7), calendar: calendar), .expiring)
        XCTAssertEqual(snapshot(normal, [batch(itemID: normal.id, lot: "A", expiry: date(2026, 9, 1), quantity: 4)]).status(warningDays: 30, now: date(2026, 10, 7), calendar: calendar), .expired)
    }

    func testExportScopeFilters() {
        let normal = item(name: "Normal", threshold: 1)
        let low = item(name: "Low", threshold: 5)
        let expiring = item(name: "Expiring", threshold: 0)
        let expired = item(name: "Expired", threshold: 0)
        let snapshots = [
            snapshot(normal, [batch(itemID: normal.id, lot: "A", expiry: date(2028, 1, 1), quantity: 4)]),
            snapshot(low, [batch(itemID: low.id, lot: "B", expiry: date(2028, 1, 1), quantity: 2)]),
            snapshot(expiring, [batch(itemID: expiring.id, lot: "C", expiry: date(2026, 10, 20), quantity: 4)]),
            snapshot(expired, [batch(itemID: expired.id, lot: "D", expiry: date(2026, 9, 1), quantity: 4)])
        ]
        func rows(_ scope: ExportScope) -> [InventoryExportRow] {
            InventoryExport.rows(snapshots: snapshots, groups: [], scope: scope, warningDays: 30, now: date(2026, 10, 7), calendar: calendar)
        }
        XCTAssertEqual(rows(.all).count, 4)
        XCTAssertEqual(rows(.lowStock).map(\.itemName), ["Low"])
        XCTAssertEqual(rows(.expiringSoon).map(\.itemName), ["Expiring"])
        XCTAssertEqual(rows(.expired).map(\.itemName), ["Expired"])
    }

    func testMovementsCSVFormatting() {
        let reagent = item(name: "ISE Mid Standard")
        let movement = StockMovement(
            id: UUID(),
            itemId: reagent.id,
            batchId: UUID(),
            type: .adjustment,
            quantityDelta: -2,
            quantityBefore: 10,
            quantityAfter: 8,
            note: "Breakage",
            lotNumberSnapshot: "2850",
            expiryDateSnapshot: date(2027, 9, 22),
            userId: userID,
            createdAt: date(2026, 10, 7)
        )
        let csv = InventoryExport.movementsCSV(
            movements: [movement],
            itemName: { _ in reagent.name },
            userName: { _ in "Ahmed" },
            generatedAt: date(2026, 10, 7)
        )
        XCTAssertTrue(csv.contains("Date,Time,Type,Item,LOT,Quantity Delta,Quantity Before,Quantity After,User,Note"))
        XCTAssertTrue(csv.contains(",Adjustment,ISE Mid Standard,2850,-2,10,8,Ahmed,Breakage"))
    }

    func testExportFileNames() {
        XCTAssertEqual(InventoryExport.fileName(prefix: "LabStock_Inventory", date: date(2026, 10, 7)), "LabStock_Inventory_2026-10-07")
        XCTAssertEqual(InventoryExport.fileName(prefix: "LabStock_History", date: date(2026, 10, 7)), "LabStock_History_2026-10-07")
    }

    func testPDFReportIsGenerated() {
        let reagent = item(name: "ISE Mid Standard", reference: "66319")
        let rows = InventoryExport.rows(
            snapshots: [snapshot(reagent, [batch(itemID: reagent.id, lot: "2850", expiry: date(2027, 9, 22), quantity: 3)])],
            groups: [],
            warningDays: 30,
            now: date(2026, 10, 7),
            calendar: calendar
        )
        let data = PDFReportBuilder.inventoryReport(rows: rows, summary: InventoryExport.summary(forRows: rows), generatedAt: date(2026, 10, 7))
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }

    // MARK: Fast AI mode

    func testFastPromptRequestsCompactSchemaOnly() {
        let prompt = DeepSeekPrompt.user
        for key in ["product_name", "manufacturer", "reference_number", "lot_number", "expiry_date", "volume_or_pack", "confidence", "field_confidence"] {
            XCTAssertTrue(prompt.contains("\"\(key)\""), "missing \(key)")
        }
        for forbidden in ["raw_label_text", "gtin", "serial_number", "manufacture_date", "catalog_number"] {
            XCTAssertFalse(prompt.contains("\"\(forbidden)\""), "fast mode should not request \(forbidden)")
        }
        XCTAssertTrue(DeepSeekPrompt.system.contains("Return JSON only"))
        XCTAssertEqual(AppConfig.deepSeekImageDetail, "original")
    }

    func testFastPayloadDecodesVolumeOrPack() throws {
        let json = """
        {"product_name": "ISE Mid Standard", "reference_number": "66319", "lot_number": "2850",
         "expiry_date": "2027-09-22", "volume_or_pack": "4 x 300 mL", "confidence": 0.91,
         "field_confidence": {"product_name": 0.95, "reference_number": 0.9, "lot_number": 0.9, "expiry_date": 0.8}}
        """
        let extraction = try XCTUnwrap(try? JSONDecoder().decode(ReagentExtraction.self, from: Data(json.utf8)))
        XCTAssertEqual(extraction.volume, "4 x 300 mL")
        XCTAssertEqual(extraction.lotNumber, "2850")
        XCTAssertEqual(extraction.referenceNumber, "66319")
        XCTAssertEqual(extraction.fieldConfidence(for: "expiry_date"), 0.8)
        XCTAssertFalse(extraction.isLowConfidence)
    }

    func testFastImageUploadBudget() {
        XCTAssertGreaterThanOrEqual(LabelImage.maxDimension, 1400)
        XCTAssertLessThanOrEqual(LabelImage.maxDimension, 1800)
        XCTAssertGreaterThanOrEqual(LabelImage.jpegQuality, 0.75)
        XCTAssertLessThanOrEqual(LabelImage.jpegQuality, 0.82)
    }
}
