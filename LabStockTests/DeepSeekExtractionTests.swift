import XCTest
import UIKit
@testable import LabStock

final class DeepSeekExtractionTests: XCTestCase {
    private func decode(_ json: String) -> ReagentExtraction? {
        try? JSONDecoder().decode(ReagentExtraction.self, from: Data(json.utf8))
    }

    func testDecodesFullPayload() throws {
        let extraction = try XCTUnwrap(decode("""
        {
          "product_name": "ISE Mid Standard",
          "manufacturer": "Roche Diagnostics",
          "reference_number": "66319",
          "catalog_number": null,
          "material_number": null,
          "lot_number": "2850",
          "expiry_date": "2027-09-22",
          "manufacture_date": null,
          "volume": "300 mL",
          "pack_size": "4 x 300 mL",
          "unit": "mL",
          "storage_temperature": "2-8 °C",
          "barcode_text": "0081234567890",
          "gtin": null,
          "serial_number": null,
          "analyzer_or_platform": "AU5800",
          "reagent_type": "calibrator",
          "raw_label_text": "ISE Mid Standard ...",
          "confidence": 0.93,
          "field_confidence": {
            "product_name": 0.95,
            "reference_number": 0.9,
            "lot_number": 0.88,
            "expiry_date": 0.8
          }
        }
        """))
        XCTAssertEqual(extraction.productName, "ISE Mid Standard")
        XCTAssertEqual(extraction.referenceNumber, "66319")
        XCTAssertEqual(extraction.lotNumber, "2850")
        XCTAssertNil(extraction.catalogNumber)
        XCTAssertNotNil(extraction.expiryDate)
        XCTAssertEqual(extraction.volume, "300 mL")
        XCTAssertEqual(extraction.storageTemperature, "2-8 °C")
        XCTAssertEqual(extraction.confidence, 0.93)
        XCTAssertEqual(extraction.fieldConfidence(for: "lot_number"), 0.88)
        XCTAssertTrue(extraction.hasUsefulData)
    }

    func testMissingKeysBecomeNil() throws {
        let extraction = try XCTUnwrap(decode(#"{"product_name": "Glucose Reagent"}"#))
        XCTAssertEqual(extraction.productName, "Glucose Reagent")
        XCTAssertNil(extraction.manufacturer)
        XCTAssertNil(extraction.referenceNumber)
        XCTAssertNil(extraction.lotNumber)
        XCTAssertNil(extraction.expiryDate)
        XCTAssertNil(extraction.confidence)
        XCTAssertNil(extraction.fieldConfidence)
    }

    func testNullAndPlaceholderStringsBecomeNil() throws {
        let extraction = try XCTUnwrap(decode("""
        {"product_name": "null", "manufacturer": "N/A", "reference_number": "  ", "lot_number": "unknown"}
        """))
        XCTAssertNil(extraction.productName)
        XCTAssertNil(extraction.manufacturer)
        XCTAssertNil(extraction.referenceNumber)
        XCTAssertNil(extraction.lotNumber)
        XCTAssertFalse(extraction.hasUsefulData)
    }

    func testNumericIdentifiersAreAccepted() throws {
        let extraction = try XCTUnwrap(decode(#"{"reference_number": 66319, "lot_number": 2850}"#))
        XCTAssertEqual(extraction.referenceNumber, "66319")
        XCTAssertEqual(extraction.lotNumber, "2850")
    }

    func testAllNullPayloadIsNotUseful() throws {
        let extraction = try XCTUnwrap(decode("""
        {"product_name": null, "manufacturer": null, "reference_number": null, "catalog_number": null,
         "material_number": null, "lot_number": null, "expiry_date": null, "barcode_text": null, "gtin": null}
        """))
        XCTAssertFalse(extraction.hasUsefulData)
    }

    func testDateNormalization() {
        XCTAssertNotNil(LabelDateParser.parse("2027-09-22"))
        XCTAssertNotNil(LabelDateParser.parse("2027/9/22"))
        XCTAssertNotNil(LabelDateParser.parse("2027.09.22"))
        XCTAssertNil(LabelDateParser.parse("2027-13-45"))
        XCTAssertNil(LabelDateParser.parse("1800-01-01"))
        XCTAssertNil(LabelDateParser.parse("no expiry"))
        XCTAssertNil(LabelDateParser.parse(""))
        XCTAssertNil(LabelDateParser.parse(nil))
    }

    func testFencedJSONIsExtractedFromAssistantContent() throws {
        let content = """
        Here is the result:
        ```json
        {"product_name": "ISE Low Standard", "lot_number": "2851"}
        ```
        """
        let extraction = try XCTUnwrap(DeepSeekExtractionDecoder.decode(content))
        XCTAssertEqual(extraction.productName, "ISE Low Standard")
        XCTAssertEqual(extraction.lotNumber, "2851")
    }

    func testAssistantContentIsReadFromChatResponse() throws {
        let payload = """
        {"choices": [{"message": {"role": "assistant", "content": "{\\"lot_number\\": \\"2850\\"}"}}]}
        """
        let content = try XCTUnwrap(ChatResponse.assistantContent(from: Data(payload.utf8)))
        let extraction = try XCTUnwrap(DeepSeekExtractionDecoder.decode(content))
        XCTAssertEqual(extraction.lotNumber, "2850")
    }

    func testMalformedAssistantContentFailsGracefully() {
        XCTAssertNil(ChatResponse.assistantContent(from: Data(#"{"choices": []}"#.utf8)))
        XCTAssertNil(DeepSeekExtractionDecoder.decode("not json at all"))
    }

    func testAPIModelIsDeepSeekFlash() {
        XCTAssertEqual(AppConfig.deepSeekModel, "deepseek-flash")
        XCTAssertEqual(AppConfig.deepSeekBaseURL.absoluteString, "https://api.deepseek.com")
    }

    func testHTTPStatusMapping() {
        XCTAssertNil(DeepSeekError.from(statusCode: 200))
        XCTAssertEqual(DeepSeekError.from(statusCode: 401), .unauthorized)
        XCTAssertEqual(DeepSeekError.from(statusCode: 429), .rateLimited)
        XCTAssertEqual(DeepSeekError.from(statusCode: 500), .server(500))
        XCTAssertEqual(DeepSeekError.from(statusCode: 400), .invalidResponse)
    }

    func testURLErrorMapping() {
        XCTAssertEqual(DeepSeekError.from(urlError: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(DeepSeekError.from(urlError: URLError(.notConnectedToInternet)), .offline)
        XCTAssertFalse(DeepSeekError.unauthorized.canRetry)
        XCTAssertTrue(DeepSeekError.timedOut.canRetry)
        XCTAssertFalse(DeepSeekError.noLabelData.message.isEmpty)
    }

    func testNativeBarcodeWinsOverAIBarcode() {
        var extraction = ReagentExtraction()
        extraction.barcodeText = "AI-VALUE"
        let analysis = ScanAnalysis(extraction: extraction, nativeBarcode: "0081234567890", localOCRText: nil, imageHash: "abc")
        XCTAssertEqual(analysis.barcode, "0081234567890")

        let aiOnly = ScanAnalysis(extraction: extraction, nativeBarcode: nil, localOCRText: nil, imageHash: "abc")
        XCTAssertEqual(aiOnly.barcode, "AI-VALUE")
    }

    func testDraftFallsBackToCatalogNumberAndCombinesPackSize() throws {
        var extraction = ReagentExtraction()
        extraction.productName = "ISE Mid Standard"
        extraction.catalogNumber = "CAT-66319"
        extraction.volume = "300 mL"
        extraction.packSize = "4 x 300 mL"
        let draft = ScanDraft(extraction: extraction, groupID: nil)
        XCTAssertEqual(draft.productName, "ISE Mid Standard")
        XCTAssertEqual(draft.referenceNumber, "CAT-66319")
        XCTAssertEqual(draft.packDescription, "300 mL / 4 x 300 mL")
    }

    func testImagePreparationResizesAndHashes() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }
        let prepared = try XCTUnwrap(LabelImage.prepare(image))
        XCTAssertFalse(prepared.data.isEmpty)
        XCTAssertEqual(prepared.hash.count, 64)
        XCTAssertEqual(prepared.hash, LabelImage.sha256(prepared.data))
        let resized = LabelImage.resized(image, maxDimension: LabelImage.maxDimension)
        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), LabelImage.maxDimension)

        let otherImage = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400)).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }
        XCTAssertNotEqual(LabelImage.prepare(image)?.hash, LabelImage.prepare(otherImage)?.hash)
    }
}
