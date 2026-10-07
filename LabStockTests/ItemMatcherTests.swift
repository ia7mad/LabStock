import XCTest
@testable import LabStock

final class ItemMatcherTests: XCTestCase {
    private let userID = UUID()

    private func item(name: String, manufacturer: String? = nil, reference: String? = nil, groupID: UUID? = nil) -> StockItem {
        StockItem(
            id: UUID(),
            groupId: groupID,
            name: name,
            manufacturer: manufacturer,
            referenceNumber: reference,
            notes: nil,
            lowStockThreshold: 1,
            unitName: "kit",
            createdAt: Date(),
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
            createdAt: Date(),
            createdBy: userID
        )
    }

    private func extraction(name: String? = nil, manufacturer: String? = nil, reference: String? = nil, catalog: String? = nil, lot: String? = nil, expiry: String? = nil) -> ReagentExtraction {
        var value = ReagentExtraction()
        value.productName = name
        value.manufacturer = manufacturer
        value.referenceNumber = reference
        value.catalogNumber = catalog
        value.lotNumber = lot
        value.expiryDate = LabelDateParser.parse(expiry)
        return value
    }

    func testBarcodeAliasWinsOverEverythingElse() {
        let existing = item(name: "ISE Mid Standard", manufacturer: "Roche", reference: "66319")
        let duplicateName = item(name: "ISE Mid Standard", manufacturer: "Roche", reference: nil)
        let matches = ItemMatcher.matches(
            for: extraction(name: "ISE Mid Standard", manufacturer: "Roche", reference: "66319"),
            aliasItemID: duplicateName.id,
            items: [existing, duplicateName]
        )
        XCTAssertEqual(matches.first?.itemID, duplicateName.id)
        XCTAssertEqual(matches.first?.kind, .barcode)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.last?.kind, .reference)
    }

    func testExactReferenceMatch() {
        let existing = item(name: "Something else", reference: "66319")
        let matches = ItemMatcher.matches(for: extraction(reference: "REF 66319"), aliasItemID: nil, items: [existing])
        XCTAssertEqual(matches, [ItemMatch(itemID: existing.id, kind: .reference)])
    }

    func testCatalogNumberMatchesReferenceField() {
        let existing = item(name: "ISE Mid Standard", reference: "CAT-66319")
        let matches = ItemMatcher.matches(for: extraction(catalog: "cat 66319"), aliasItemID: nil, items: [existing])
        XCTAssertEqual(matches.first?.itemID, existing.id)
        XCTAssertEqual(matches.first?.kind, .catalog)
    }

    func testManufacturerAndNameMatch() {
        let existing = item(name: "ISE Mid Standard", manufacturer: "Roche Diagnostics")
        let matches = ItemMatcher.matches(
            for: extraction(name: "ise  mid standard", manufacturer: "roche diagnostics"),
            aliasItemID: nil,
            items: [existing]
        )
        XCTAssertEqual(matches.first?.kind, .name)
    }

    func testFuzzyNameIsOnlyASuggestion() {
        let existing = item(name: "ISE Mid Standard 300 mL")
        let matches = ItemMatcher.matches(for: extraction(name: "ISE Mid Standard"), aliasItemID: nil, items: [existing])
        XCTAssertEqual(matches.first?.kind, .fuzzy)
    }

    func testNoMatchForUnrelatedItem() {
        let existing = item(name: "Glucose Reagent", manufacturer: "Abbott", reference: "9D01")
        let matches = ItemMatcher.matches(for: extraction(name: "ISE Mid Standard", reference: "66319"), aliasItemID: nil, items: [existing])
        XCTAssertTrue(matches.isEmpty)
    }

    func testMatchIsDeduplicatedPerItem() {
        let existing = item(name: "ISE Mid Standard", manufacturer: "Roche", reference: "66319")
        let matches = ItemMatcher.matches(
            for: extraction(name: "ISE Mid Standard", manufacturer: "Roche", reference: "66319"),
            aliasItemID: nil,
            items: [existing]
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.kind, .reference)
    }

    func testBatchMatchPrefersLotAndExpiry() {
        let itemID = UUID()
        let expiry = LabelDateParser.parse("2027-09-22")
        let exact = batch(itemID: itemID, lot: "2850", expiry: expiry, quantity: 4)
        let sameLotOtherExpiry = batch(itemID: itemID, lot: "2850", expiry: LabelDateParser.parse("2028-09-22"), quantity: 2)
        let otherLot = batch(itemID: itemID, lot: "2851", expiry: expiry, quantity: 9)

        let matches = BatchMatcher.matches(itemID: itemID, lotNumber: "2850", expiryDate: expiry, in: [sameLotOtherExpiry, exact, otherLot])
        XCTAssertEqual(matches.map(\.id), [exact.id])
        XCTAssertEqual(BatchMatcher.best(itemID: itemID, lotNumber: "2850", expiryDate: expiry, in: [sameLotOtherExpiry, exact, otherLot])?.id, exact.id)
    }

    func testBatchMatchFallsBackToLotThenExpiry() {
        let itemID = UUID()
        let expiry = LabelDateParser.parse("2027-09-22")
        let lotOnly = batch(itemID: itemID, lot: "2850", expiry: LabelDateParser.parse("2028-01-01"), quantity: 3)
        let expiryOnly = batch(itemID: itemID, lot: "9999", expiry: expiry, quantity: 5)
        let batches = [lotOnly, expiryOnly]

        XCTAssertEqual(BatchMatcher.matches(itemID: itemID, lotNumber: "2850", expiryDate: expiry, in: batches).map(\.id), [lotOnly.id])
        XCTAssertEqual(BatchMatcher.matches(itemID: itemID, lotNumber: nil, expiryDate: expiry, in: batches).map(\.id), [expiryOnly.id])
    }

    func testMultipleLotCandidatesAreReturnedForPicker() {
        let itemID = UUID()
        let first = batch(itemID: itemID, lot: "2850", expiry: nil, quantity: 3)
        let second = batch(itemID: itemID, lot: "2850", expiry: nil, quantity: 1)
        let matches = BatchMatcher.matches(itemID: itemID, lotNumber: "2850", expiryDate: nil, in: [first, second])
        XCTAssertEqual(Set(matches.map(\.id)), Set([first.id, second.id]))
    }

    func testWithdrawWithoutLotFallsBackToFEFO() {
        let itemID = UUID()
        let near = batch(itemID: itemID, lot: "A", expiry: LabelDateParser.parse("2027-01-01"), quantity: 2)
        let far = batch(itemID: itemID, lot: "B", expiry: LabelDateParser.parse("2028-01-01"), quantity: 7)
        XCTAssertEqual(BatchMatcher.best(itemID: itemID, lotNumber: nil, expiryDate: nil, in: [far, near])?.id, near.id)
    }

    func testUnknownLotCreatesNoMatch() {
        let itemID = UUID()
        let batches = [batch(itemID: itemID, lot: "2850", expiry: nil, quantity: 3)]
        XCTAssertTrue(BatchMatcher.matches(itemID: itemID, lotNumber: "7777", expiryDate: LabelDateParser.parse("2027-01-01"), in: batches).isEmpty)
        XCTAssertNil(BatchMatcher.best(itemID: itemID, lotNumber: "7777", expiryDate: nil, in: []))
    }
}
