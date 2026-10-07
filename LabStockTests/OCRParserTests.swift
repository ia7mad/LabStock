import XCTest
@testable import LabStock

final class OCRParserTests: XCTestCase {
    func testParsesCommonReagentLabel() {
        let fields = OCRParser.parse("""
        ISE Mid Standard
        Manufacturer: Roche Diagnostics
        REF 66319
        LOT 2850
        EXP 2027-09-22
        """)
        XCTAssertEqual(fields.name, "ISE Mid Standard")
        XCTAssertEqual(fields.manufacturer, "Roche Diagnostics")
        XCTAssertEqual(fields.referenceNumber, "66319")
        XCTAssertEqual(fields.lotNumber, "2850")
        XCTAssertNotNil(fields.expiryDate)
    }

    func testDoesNotInventMissingValues() {
        let fields = OCRParser.parse("Glucose Reagent\nStore refrigerated")
        XCTAssertEqual(fields.name, "Glucose Reagent")
        XCTAssertEqual(fields.referenceNumber, "")
        XCTAssertEqual(fields.lotNumber, "")
        XCTAssertNil(fields.expiryDate)
    }
}
