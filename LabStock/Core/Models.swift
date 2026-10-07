import Foundation

enum MovementType: String, Codable, CaseIterable, Identifiable {
    case add, withdraw, adjustment, inventory
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AliasType: String, Codable { case barcode, ref, text }
enum InventorySessionStatus: String, Codable { case active, completed }

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String?
    var expiryWarningDays: Int
    var notificationsEnabled: Bool
    let createdAt: Date
}

struct InventoryGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    let createdBy: UUID
}

struct StockItem: Codable, Identifiable, Hashable {
    let id: UUID
    var groupId: UUID?
    var name: String
    var manufacturer: String?
    var referenceNumber: String?
    var notes: String?
    var lowStockThreshold: Int
    var unitName: String
    let createdAt: Date
    let createdBy: UUID
}

struct Batch: Codable, Identifiable, Hashable {
    let id: UUID
    let itemId: UUID
    var lotNumber: String?
    var expiryDate: Date?
    var currentQuantity: Int
    let createdAt: Date
    let createdBy: UUID
}

struct ScanAlias: Codable, Identifiable {
    let id: UUID
    let itemId: UUID
    let type: AliasType
    let value: String
    let normalizedValue: String
    let createdAt: Date
    let createdBy: UUID
}

struct StockMovement: Codable, Identifiable {
    let id: UUID
    let itemId: UUID
    let batchId: UUID?
    let type: MovementType
    let quantityDelta: Int
    let quantityBefore: Int
    let quantityAfter: Int
    let note: String?
    let lotNumberSnapshot: String?
    let expiryDateSnapshot: Date?
    let userId: UUID
    let createdAt: Date
}

struct InventorySession: Codable, Identifiable {
    let id: UUID
    let groupId: UUID?
    let status: InventorySessionStatus
    let startedBy: UUID
    let startedAt: Date
    let completedAt: Date?
}

struct InventoryCount: Codable, Identifiable, Hashable {
    let id: UUID
    let sessionId: UUID
    let itemId: UUID
    let batchId: UUID?
    let expectedQuantity: Int
    var countedQuantity: Int
    let createdAt: Date
}

struct ItemSnapshot: Identifiable, Hashable {
    let item: StockItem
    var batches: [Batch]
    var id: UUID { item.id }
    var totalQuantity: Int { batches.reduce(0) { $0 + $1.currentQuantity } }
    var nearestExpiry: Date? { batches.compactMap(\.expiryDate).min() }
}

struct DashboardSummary {
    var totalItems = 0
    var lowStock = 0
    var expiringSoon = 0
    var expired = 0
}

struct OCRFields: Equatable {
    var name = ""
    var manufacturer = ""
    var referenceNumber = ""
    var lotNumber = ""
    var expiryDate: Date?
}

/// Structured label extraction returned by the DeepSeek vision model.
/// Every field is optional: the model returns `null` instead of guessing.
struct ReagentExtraction: Codable, Equatable {
    var productName: String?
    var manufacturer: String?
    var referenceNumber: String?
    var catalogNumber: String?
    var materialNumber: String?
    var lotNumber: String?
    var expiryDate: Date?
    var manufactureDate: Date?
    var volume: String?
    var packSize: String?
    var unit: String?
    var storageTemperature: String?
    var barcodeText: String?
    var gtin: String?
    var serialNumber: String?
    var analyzerOrPlatform: String?
    var reagentType: String?
    var rawLabelText: String?
    var confidence: Double?
    var fieldConfidence: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case manufacturer
        case referenceNumber = "reference_number"
        case catalogNumber = "catalog_number"
        case materialNumber = "material_number"
        case lotNumber = "lot_number"
        case expiryDate = "expiry_date"
        case manufactureDate = "manufacture_date"
        case volume
        case packSize = "pack_size"
        case unit
        case storageTemperature = "storage_temperature"
        case barcodeText = "barcode_text"
        case gtin
        case serialNumber = "serial_number"
        case analyzerOrPlatform = "analyzer_or_platform"
        case reagentType = "reagent_type"
        case rawLabelText = "raw_label_text"
        case confidence
        case fieldConfidence = "field_confidence"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func text(_ key: CodingKeys) -> String? {
            if let decoded = try? container.decodeIfPresent(String.self, forKey: key) {
                guard let value = decoded else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let lowered = trimmed.lowercased()
                guard !trimmed.isEmpty, lowered != "null", lowered != "n/a", lowered != "unknown" else { return nil }
                return trimmed
            }
            if let decoded = try? container.decodeIfPresent(Double.self, forKey: key), let value = decoded {
                return value == value.rounded() ? String(Int(value)) : String(value)
            }
            return nil
        }

        func number(_ key: CodingKeys) -> Double? {
            if let decoded = try? container.decodeIfPresent(Double.self, forKey: key), let value = decoded { return value }
            if let decoded = try? container.decodeIfPresent(String.self, forKey: key), let value = decoded {
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        productName = text(.productName)
        manufacturer = text(.manufacturer)
        referenceNumber = text(.referenceNumber)
        catalogNumber = text(.catalogNumber)
        materialNumber = text(.materialNumber)
        lotNumber = text(.lotNumber)
        expiryDate = LabelDateParser.parse(text(.expiryDate))
        manufactureDate = LabelDateParser.parse(text(.manufactureDate))
        volume = text(.volume)
        packSize = text(.packSize)
        unit = text(.unit)
        storageTemperature = text(.storageTemperature)
        barcodeText = text(.barcodeText)
        gtin = text(.gtin)
        serialNumber = text(.serialNumber)
        analyzerOrPlatform = text(.analyzerOrPlatform)
        reagentType = text(.reagentType)
        rawLabelText = text(.rawLabelText)
        confidence = number(.confidence)
        fieldConfidence = try? container.decodeIfPresent([String: Double].self, forKey: .fieldConfidence)
    }

    /// True when the model returned nothing usable for inventory.
    var hasUsefulData: Bool {
        productName != nil || referenceNumber != nil || catalogNumber != nil || materialNumber != nil
            || lotNumber != nil || manufacturer != nil || barcodeText != nil || gtin != nil
    }

    var referenceOrCatalog: String? { referenceNumber ?? catalogNumber ?? materialNumber }

    func fieldConfidence(for key: String) -> Double? { fieldConfidence?[key] }

    /// Effective confidence used to decide how much the user must review.
    var effectiveConfidence: Double {
        if let confidence, confidence > 0 { return confidence }
        let values = (fieldConfidence ?? [:]).values
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    var isLowConfidence: Bool { effectiveConfidence > 0 && effectiveConfidence < 0.5 }
}

/// Normalizes the loose date strings a label can contain into a real Date.
enum LabelDateParser {
    private static let formats = [
        "yyyy-MM-dd", "yyyy-M-d", "yyyy/MM/dd", "yyyy/M/d", "yyyy.MM.dd", "yyyy.M.d",
        "dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy",
        "MM/yyyy", "MM-yyyy", "yyyy-MM", "yyyy/MM"
    ]

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
        guard !value.isEmpty else { return nil }
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: value), isPlausible(date) { return date }
        }
        if let date = ISO8601DateFormatter.labStockBasic.date(from: value), isPlausible(date) { return date }
        return nil
    }

    private static func isPlausible(_ date: Date) -> Bool {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return (1990...2100).contains(year)
    }
}

/// Result of one scan: AI extraction plus native/local detections.
struct ScanAnalysis: Equatable {
    var extraction: ReagentExtraction
    var nativeBarcode: String?
    var localOCRText: String?
    var imageHash: String

    /// Native decoders always win over the model's transcribed barcode text.
    var barcode: String? { nativeBarcode?.nilIfBlank ?? extraction.barcodeText?.nilIfBlank }
}

/// A likely existing inventory item found before creating anything new.
struct ItemMatch: Equatable {
    enum Kind: String {
        case barcode, reference, catalog, name, fuzzy
        var priority: Int {
            switch self {
            case .barcode: 1
            case .reference: 2
            case .catalog: 3
            case .name: 4
            case .fuzzy: 5
            }
        }
        var label: String {
            switch self {
            case .barcode: "Known barcode"
            case .reference: "Matching REF"
            case .catalog: "Matching catalog number"
            case .name: "Matching name"
            case .fuzzy: "Similar name"
            }
        }
    }

    let itemID: UUID
    let kind: Kind
}

/// A ranked match resolved to a real inventory item (used by the review screen).
struct ScannedItemMatch: Identifiable, Equatable {
    let match: ItemMatch
    let item: StockItem
    var id: UUID { item.id }
}

/// Editable label fields shown on the confirmation screen.
struct ScanDraft: Equatable {
    var productName = ""
    var manufacturer = ""
    var referenceNumber = ""
    var lotNumber = ""
    var expiryDate: Date?
    var volume = ""
    var unit = ""
    var storageTemperature = ""
    var groupID: UUID?
    var quantity = 1

    init() {}

    init(extraction: ReagentExtraction, groupID: UUID?) {
        productName = extraction.productName ?? ""
        manufacturer = extraction.manufacturer ?? ""
        referenceNumber = extraction.referenceOrCatalog ?? ""
        lotNumber = extraction.lotNumber ?? ""
        expiryDate = extraction.expiryDate
        volume = [extraction.volume, extraction.packSize].compactMap { $0 }.joined(separator: " / ")
        unit = extraction.unit ?? ""
        storageTemperature = extraction.storageTemperature ?? ""
        self.groupID = groupID
    }

    var packDescription: String? { volume.nilIfBlank }
}

struct NewGroupPayload: Encodable { let name: String; let createdBy: UUID }
struct UpdateGroupPayload: Encodable { let name: String }
struct UpdateProfilePayload: Encodable {
    let expiryWarningDays: Int
    let notificationsEnabled: Bool
}
struct NewItemPayload: Encodable {
    let groupId: UUID?
    let name: String
    let manufacturer: String?
    let referenceNumber: String?
    let notes: String?
    let lowStockThreshold: Int
    let unitName: String
    let createdBy: UUID
}
struct NewBatchPayload: Encodable {
    let itemId: UUID
    let lotNumber: String?
    let expiryDate: String?
    let currentQuantity: Int = 0
    let createdBy: UUID
}
struct NewAliasPayload: Encodable { let itemId: UUID; let type: AliasType; let value: String; let createdBy: UUID }
struct NewSessionPayload: Encodable {
    let groupId: UUID?
    let status: InventorySessionStatus = .active
    let startedBy: UUID
}
struct NewCountPayload: Encodable {
    let sessionId: UUID
    let itemId: UUID
    let batchId: UUID
    let expectedQuantity: Int
    let countedQuantity: Int = 0
}
struct UpdateCountPayload: Encodable { let countedQuantity: Int }

extension JSONDecoder {
    static var labStock: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.labStock.date(from: value) { return date }
            if let date = ISO8601DateFormatter.labStockBasic.date(from: value) { return date }
            if let date = DateFormatter.sqlDate.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var labStock: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension ISO8601DateFormatter {
    static let labStock: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let labStockBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension DateFormatter {
    static let sqlDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
