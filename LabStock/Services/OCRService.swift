import Foundation
import UIKit
import Vision

enum OCRParser {
    private static let refPattern = #"(?i)\b(?:REF|CAT(?:ALOG)?(?:\s*NO)?)(?=[\s:#-]|\d)[\s:#-]*([A-Z0-9][A-Z0-9._/-]{2,})"#
    private static let lotPattern = #"(?i)\b(?:LOT|BATCH)(?=[\s:#-]|\d)[\s:#-]*([A-Z0-9][A-Z0-9._/-]{1,})"#
    private static let expiryPattern = #"(?i)\b(?:EXP(?:IRY|IRES)?|USE\s*BY|BEST\s*BEFORE)(?=[\s:#-]|\d)[\s:#-]*(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})"#
    private static let makerPattern = #"(?im)\b(?:MANUFACTURER|MFR|MADE\s+BY)\b[\s:#-]*(.+)$"#

    static func parse(_ text: String) -> OCRFields {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var fields = OCRFields()
        fields.referenceNumber = capture(refPattern, in: text) ?? ""
        fields.lotNumber = capture(lotPattern, in: text) ?? ""
        fields.manufacturer = capture(makerPattern, in: text) ?? ""
        if let rawDate = capture(expiryPattern, in: text) { fields.expiryDate = parseDate(rawDate) }
        fields.name = lines.first(where: { line in
            line.count >= 3 && line.range(of: refPattern, options: .regularExpression) == nil
                && line.range(of: lotPattern, options: .regularExpression) == nil
                && line.range(of: expiryPattern, options: .regularExpression) == nil
                && line.range(of: makerPattern, options: .regularExpression) == nil
                && line.rangeOfCharacter(from: .letters) != nil
        }) ?? ""
        return fields
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let normalized = raw.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
        let formats = normalized.first?.isNumber == true && normalized.prefix(4).allSatisfy { $0.isNumber }
            ? ["yyyy-M-d"] : ["dd-M-yyyy", "dd-M-yy", "MM-dd-yyyy", "MM-dd-yy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: normalized) { return date }
        }
        return nil
    }
}

enum OCRService {
    static func recognize(image: UIImage) async throws -> OCRFields {
        OCRParser.parse(try await recognizeText(image: image))
    }

    /// Raw on-device text. Used only as a hint/fallback for the AI analysis.
    static func recognizeText(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw LabStockError.cameraUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
