import Foundation

/// Matches AI-extracted label data against existing inventory before creating anything.
/// Pure logic so it stays testable without a network.
enum ItemMatcher {
    static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let scalars = value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let result = String(String.UnicodeScalarView(scalars))
        return result.isEmpty ? nil : result
    }

    /// Identifier comparison drops leading keywords such as "REF", "CAT" and "NO."
    /// so "REF 66319" matches a stored "66319".
    static func identifier(_ value: String?) -> String? {
        guard var text = value?.lowercased() else { return nil }
        for prefix in ["catalog", "material", "reference", "ref", "cat", "number", "num", "no"] {
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        return normalize(text)
    }

    static func lot(_ value: String?) -> String? {
        guard let value else { return nil }
        let scalars = value.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let result = String(String.UnicodeScalarView(scalars))
        return result.isEmpty ? nil : result
    }

    /// Ranked, de-duplicated matches. Lowest `priority` wins per item.
    static func matches(for extraction: ReagentExtraction, aliasItemID: UUID?, items: [StockItem]) -> [ItemMatch] {
        var best: [UUID: ItemMatch] = [:]

        func register(_ item: StockItem, _ kind: ItemMatch.Kind) {
            if let existing = best[item.id], existing.kind.priority <= kind.priority { return }
            best[item.id] = ItemMatch(itemID: item.id, kind: kind)
        }

        if let aliasItemID, let item = items.first(where: { $0.id == aliasItemID }) {
            register(item, .barcode)
        }

        if let reference = identifier(extraction.referenceNumber) {
            for item in items where identifier(item.referenceNumber) == reference { register(item, .reference) }
        }

        if let catalog = identifier(extraction.catalogNumber) ?? identifier(extraction.materialNumber) {
            for item in items where identifier(item.referenceNumber) == catalog { register(item, .catalog) }
        }

        if let name = normalize(extraction.productName) {
            let maker = normalize(extraction.manufacturer)
            for item in items where normalize(item.name) == name {
                if maker == nil || normalize(item.manufacturer) == maker { register(item, .name) }
            }
            for item in items {
                guard let itemName = normalize(item.name) else { continue }
                if itemName.contains(name) || name.contains(itemName) { register(item, .fuzzy) }
            }
        }

        return best.values.sorted { lhs, rhs in
            if lhs.kind.priority != rhs.kind.priority { return lhs.kind.priority < rhs.kind.priority }
            return lhs.itemID.uuidString < rhs.itemID.uuidString
        }
    }
}

/// Resolves which batch a scan belongs to (LOT + expiry first, then LOT, then expiry).
enum BatchMatcher {
    static func matches(itemID: UUID, lotNumber: String?, expiryDate: Date?, in batches: [Batch]) -> [Batch] {
        let candidates = batches.filter { $0.itemId == itemID }
        guard !candidates.isEmpty else { return [] }
        let lot = ItemMatcher.lot(lotNumber)
        let day = expiryDate.map { Calendar.current.startOfDay(for: $0) }

        func expiryMatches(_ batch: Batch) -> Bool {
            guard let day else { return batch.expiryDate == nil }
            guard let expiry = batch.expiryDate else { return false }
            return Calendar.current.startOfDay(for: expiry) == day
        }

        if let lot {
            let exact = candidates.filter { ItemMatcher.lot($0.lotNumber) == lot && expiryMatches($0) }
            if !exact.isEmpty { return exact }
            let lotOnly = candidates.filter { ItemMatcher.lot($0.lotNumber) == lot }
            if !lotOnly.isEmpty { return lotOnly }
        }

        if day != nil {
            let expiryOnly = candidates.filter { expiryMatches($0) }
            if !expiryOnly.isEmpty { return expiryOnly }
        }

        return []
    }

    static func best(itemID: UUID, lotNumber: String?, expiryDate: Date?, in batches: [Batch]) -> Batch? {
        let found = matches(itemID: itemID, lotNumber: lotNumber, expiryDate: expiryDate, in: batches)
        if found.count == 1 { return found.first }
        if found.isEmpty {
            return InventoryRules.preferredFEFOBatch(from: batches.filter { $0.itemId == itemID })
        }
        return InventoryRules.preferredFEFOBatch(from: found) ?? found.first
    }
}
