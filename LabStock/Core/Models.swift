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
