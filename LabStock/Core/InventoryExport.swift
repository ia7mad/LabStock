import Foundation

enum ExportScope: String, CaseIterable, Identifiable {
    case all = "All Inventory"
    case group = "Selected Group"
    case lowStock = "Low Stock"
    case expiringSoon = "Expiring Soon"
    case expired = "Expired"

    var id: String { rawValue }
}

enum ExportStatus: String {
    case normal = "NORMAL"
    case lowStock = "LOW STOCK"
    case expiring = "EXPIRING"
    case expired = "EXPIRED"
}

struct InventoryExportRow: Equatable {
    var group: String
    var itemName: String
    var manufacturer: String
    var reference: String
    var lot: String
    var expiry: Date?
    var quantity: Int
    var unit: String
    var status: ExportStatus
}

extension ItemSnapshot {
    /// Single status badge value for a whole item (worst case wins).
    func status(warningDays: Int, now: Date = .now, calendar: Calendar = .current) -> ExportStatus {
        let statuses = batches.map {
            InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays, now: now, calendar: calendar)
        }
        if statuses.contains(.expired) { return .expired }
        if statuses.contains(.expiringSoon) { return .expiring }
        return totalQuantity <= item.lowStockThreshold ? .lowStock : .normal
    }
}

struct InventoryExportSummary: Equatable {
    var totalItems = 0
    var totalBatches = 0
    var totalQuantity = 0
    var lowStock = 0
    var expiringSoon = 0
    var expired = 0

    static func make(snapshots: [ItemSnapshot], warningDays: Int, now: Date = .now, calendar: Calendar = .current) -> InventoryExportSummary {
        var summary = InventoryExportSummary()
        summary.totalItems = snapshots.count
        for snapshot in snapshots {
            summary.totalBatches += snapshot.batches.count
            summary.totalQuantity += snapshot.totalQuantity
            if snapshot.totalQuantity <= snapshot.item.lowStockThreshold { summary.lowStock += 1 }
            let statuses = snapshot.batches.map { InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays, now: now, calendar: calendar) }
            if statuses.contains(.expired) { summary.expired += 1 }
            else if statuses.contains(.expiringSoon) { summary.expiringSoon += 1 }
        }
        return summary
    }
}

/// Pure export logic: one row per batch, Excel-friendly CSV, shareable filenames.
enum InventoryExport {
    static func status(for snapshot: ItemSnapshot, batch: Batch, warningDays: Int, now: Date = .now, calendar: Calendar = .current) -> ExportStatus {
        switch InventoryRules.expiryStatus(for: batch.expiryDate, warningDays: warningDays, now: now, calendar: calendar) {
        case .expired: return .expired
        case .expiringSoon: return .expiring
        default:
            return snapshot.totalQuantity <= snapshot.item.lowStockThreshold ? .lowStock : .normal
        }
    }

    static func rows(
        snapshots: [ItemSnapshot],
        groups: [InventoryGroup],
        scope: ExportScope = .all,
        groupID: UUID? = nil,
        warningDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [InventoryExportRow] {
        var rows: [InventoryExportRow] = []
        for snapshot in snapshots {
            guard scope != .group || snapshot.item.groupId == groupID else { continue }
            let groupName = snapshot.item.groupId.flatMap { id in groups.first(where: { $0.id == id })?.name } ?? "Ungrouped"
            let batches = snapshot.batches
            let statuses = batches.map { status(for: snapshot, batch: $0, warningDays: warningDays, now: now, calendar: calendar) }

            switch scope {
            case .lowStock where snapshot.totalQuantity > snapshot.item.lowStockThreshold:
                continue
            case .expiringSoon where !statuses.contains(.expiring):
                continue
            case .expired where !statuses.contains(.expired):
                continue
            default:
                break
            }

            if batches.isEmpty {
                rows.append(InventoryExportRow(
                    group: groupName,
                    itemName: snapshot.item.name,
                    manufacturer: snapshot.item.manufacturer ?? "",
                    reference: snapshot.item.referenceNumber ?? "",
                    lot: "",
                    expiry: nil,
                    quantity: 0,
                    unit: snapshot.item.unitName,
                    status: snapshot.totalQuantity <= snapshot.item.lowStockThreshold ? .lowStock : .normal
                ))
                continue
            }

            for (index, batch) in batches.enumerated() {
                let status = statuses[index]
                if scope == .expiringSoon, status != .expiring { continue }
                if scope == .expired, status != .expired { continue }
                rows.append(InventoryExportRow(
                    group: groupName,
                    itemName: snapshot.item.name,
                    manufacturer: snapshot.item.manufacturer ?? "",
                    reference: snapshot.item.referenceNumber ?? "",
                    lot: batch.lotNumber ?? "",
                    expiry: batch.expiryDate,
                    quantity: batch.currentQuantity,
                    unit: snapshot.item.unitName,
                    status: status
                ))
            }
        }
        return rows
    }

    // MARK: CSV

    static func inventoryCSV(rows: [InventoryExportRow], summary: InventoryExportSummary, generatedAt: Date = .now) -> String {
        var lines: [String] = []
        lines.append("Group,Item Name,Manufacturer,REF,LOT,Expiry,Quantity,Unit,Status")
        for row in rows {
            lines.append([
                csvField(row.group),
                csvField(row.itemName),
                csvField(row.manufacturer),
                csvField(row.reference),
                csvField(row.lot),
                csvField(row.expiry.map { dateField.string(from: $0) } ?? ""),
                "\(row.quantity)",
                csvField(row.unit),
                csvField(row.status.rawValue)
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append("Summary")
        lines.append("Total Items,\(summary.totalItems)")
        lines.append("Total Batches,\(summary.totalBatches)")
        lines.append("Total Quantity,\(summary.totalQuantity)")
        lines.append("Low Stock,\(summary.lowStock)")
        lines.append("Expiring Soon,\(summary.expiringSoon)")
        lines.append("Expired,\(summary.expired)")
        lines.append("Generated,\(csvField(stampField.string(from: generatedAt)))")
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func movementsCSV(
        movements: [StockMovement],
        itemName: (UUID) -> String,
        userName: (UUID) -> String,
        generatedAt: Date = .now
    ) -> String {
        var lines: [String] = []
        lines.append("Date,Time,Type,Item,LOT,Quantity Delta,Quantity Before,Quantity After,User,Note")
        for movement in movements {
            lines.append([
                csvField(dateField.string(from: movement.createdAt)),
                csvField(timeField.string(from: movement.createdAt)),
                csvField(movement.type.rawValue.capitalized),
                csvField(itemName(movement.itemId)),
                csvField(movement.lotNumberSnapshot ?? ""),
                "\(movement.quantityDelta)",
                "\(movement.quantityBefore)",
                "\(movement.quantityAfter)",
                csvField(userName(movement.userId)),
                csvField(movement.note ?? "")
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append("Generated,\(csvField(stampField.string(from: generatedAt)))")
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 escaping so files open cleanly in Excel/Numbers/Sheets.
    static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func fileName(prefix: String, date: Date = .now) -> String {
        "\(prefix)_\(dateField.string(from: date))"
    }

    /// Summary derived from the exported rows so it always matches the file contents.
    static func summary(forRows rows: [InventoryExportRow]) -> InventoryExportSummary {
        var summary = InventoryExportSummary()
        summary.totalBatches = rows.count
        summary.totalQuantity = rows.reduce(0) { $0 + $1.quantity }
        summary.totalItems = Set(rows.map(\.itemName)).count
        summary.lowStock = Set(rows.filter { $0.status == .lowStock }.map(\.itemName)).count
        summary.expiringSoon = Set(rows.filter { $0.status == .expiring }.map(\.itemName)).count
        summary.expired = Set(rows.filter { $0.status == .expired }.map(\.itemName)).count
        return summary
    }

    /// Writes export output into the temporary directory so the share sheet can hand it off.
    static func writeTemporaryFile(named name: String, contents: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func writeTemporaryFile(named name: String, text: String) -> URL? {
        writeTemporaryFile(named: name, contents: Data(text.utf8))
    }

    static let dateField: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let timeField: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let stampField: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
