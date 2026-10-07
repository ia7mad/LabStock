import Foundation
import UIKit

@MainActor
final class InventoryStore: ObservableObject {
    @Published var userID: UUID?
    @Published var profiles: [Profile] = []
    @Published var groups: [InventoryGroup] = []
    @Published var items: [StockItem] = []
    @Published var batches: [Batch] = []
    @Published var movements: [StockMovement] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = SupabaseService.shared
    private var refreshTask: Task<Void, Never>?

    var snapshots: [ItemSnapshot] {
        items.map { item in ItemSnapshot(item: item, batches: batches.filter { $0.itemId == item.id }) }
    }

    var currentProfile: Profile? { profiles.first(where: { $0.id == userID }) }

    func displayName(for userID: UUID) -> String {
        if let name = profiles.first(where: { $0.id == userID })?.displayName?.nilIfBlank { return name }
        return userID == self.userID ? "Me" : String(userID.uuidString.prefix(8))
    }

    func bootstrap() async {
        guard AppConfig.isConfigured else { return }
        userID = await service.currentUserID()
        guard userID != nil else { return }
        await refresh()
        do { try await service.startRealtime { [weak self] in await self?.debouncedRefresh() } }
        catch { errorMessage = error.localizedDescription }
    }

    func signIn(email: String, password: String) async throws {
        userID = try await service.signIn(email: email, password: password)
        await refresh()
        try await service.startRealtime { [weak self] in await self?.debouncedRefresh() }
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> Bool {
        let registeredID = try await service.signUp(email: email, password: password, displayName: displayName)
        guard let registeredID else { return false }
        userID = registeredID
        await refresh()
        try await service.startRealtime { [weak self] in
            await self?.debouncedRefresh()
        }
        return true
    }

    func signOut() async {
        do { try await service.signOut() }
        catch { errorMessage = error.localizedDescription }
        userID = nil
        profiles = []; groups = []; items = []; batches = []; movements = []
    }

    func refresh() async {
        guard userID != nil else { return }
        isLoading = true
        do {
            async let fetchedGroups = service.fetchGroups()
            async let fetchedProfiles = service.fetchProfiles()
            async let fetchedItems = service.fetchItems()
            async let fetchedBatches = service.fetchBatches()
            async let fetchedMovements = service.fetchMovements()
            groups = try await fetchedGroups
            profiles = try await fetchedProfiles
            items = try await fetchedItems
            batches = try await fetchedBatches
            movements = try await fetchedMovements
            if let profile = currentProfile {
                UserDefaults.standard.set(profile.expiryWarningDays, forKey: "expiryWarningDays")
                UserDefaults.standard.set(profile.notificationsEnabled, forKey: "notificationsEnabled")
            }
            await NotificationService.shared.reschedule(snapshots: snapshots)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func debouncedRefresh() async {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func createGroup(name: String) async throws {
        guard let userID, let clean = name.nilIfBlank else { return }
        _ = try await service.createGroup(name: clean, userID: userID)
        await refresh()
    }

    func renameGroup(_ group: InventoryGroup, name: String) async throws {
        guard let clean = name.nilIfBlank else { return }
        try await service.renameGroup(id: group.id, name: clean)
        await refresh()
    }

    func deleteGroup(_ group: InventoryGroup) async throws {
        try await service.deleteGroup(id: group.id)
        await refresh()
    }

    func createItem(name: String, groupID: UUID?, manufacturer: String? = nil, referenceNumber: String? = nil, notes: String? = nil, lowStockThreshold: Int = 1, unitName: String = "unit") async throws {
        guard let userID, let clean = name.nilIfBlank else { return }
        let item = try await service.createItem(NewItemPayload(
            groupId: groupID, name: clean, manufacturer: manufacturer?.nilIfBlank,
            referenceNumber: referenceNumber?.nilIfBlank, notes: notes?.nilIfBlank,
            lowStockThreshold: max(0, lowStockThreshold), unitName: unitName.nilIfBlank ?? "unit", createdBy: userID
        ))
        if let reference = referenceNumber?.nilIfBlank {
            try await service.createAlias(itemID: item.id, type: .ref, value: reference)
        }
        await refresh()
    }

    func updatePreferences(warningDays: Int, notificationsEnabled: Bool) async throws {
        guard let userID else { return }
        try await service.updateProfile(
            userID: userID,
            warningDays: max(1, warningDays),
            notificationsEnabled: notificationsEnabled
        )
        await refresh()
    }

    func recognize(_ value: String) async throws -> ItemSnapshot? {
        guard let item = try await service.recognize(alias: value) else { return nil }
        return ItemSnapshot(item: item, batches: batches.filter { $0.itemId == item.id })
    }

    func applyStock(itemID: UUID, batchID: UUID?, newLot: String?, newExpiry: Date?, delta: Int, type: MovementType, note: String? = nil) async throws {
        let batch: Batch
        if let batchID, let existing = batches.first(where: { $0.id == batchID }) {
            batch = existing
        } else {
            batch = try await service.createBatch(itemID: itemID, lot: newLot, expiry: newExpiry)
        }
        guard InventoryRules.validate(delta: delta, current: batch.currentQuantity) else {
            throw LabStockError.invalidQuantity
        }
        try await service.applyStock(batchID: batch.id, delta: delta, type: type, note: note)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await refresh()
    }

    func createScanned(fields: OCRFields, groupID: UUID?, barcode: String?, quantity: Int) async throws {
        guard fields.name.nilIfBlank != nil, quantity > 0 else { throw LabStockError.invalidQuantity }
        _ = try await service.createScannedItem(fields: fields, groupID: groupID, barcode: barcode, quantity: quantity)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await refresh()
    }

    func dashboard(warningDays: Int) -> DashboardSummary {
        var summary = DashboardSummary(totalItems: items.count)
        for snapshot in snapshots {
            if snapshot.totalQuantity <= snapshot.item.lowStockThreshold { summary.lowStock += 1 }
            let statuses = snapshot.batches.map { InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays) }
            if statuses.contains(.expired) { summary.expired += 1 }
            else if statuses.contains(.expiringSoon) { summary.expiringSoon += 1 }
        }
        return summary
    }

    func startInventory(groupID: UUID?) async throws -> (UUID, [InventoryCount]) {
        let sessionID = try await service.startInventory(groupID: groupID)
        return (sessionID, try await service.fetchCounts(sessionID: sessionID))
    }

    func updateCount(_ count: InventoryCount, quantity: Int) async throws -> InventoryCount {
        var updated = count
        updated.countedQuantity = max(0, quantity)
        try await service.setCount(count, quantity: updated.countedQuantity)
        return updated
    }

    func completeInventory(sessionID: UUID) async throws {
        try await service.completeInventory(sessionID: sessionID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await refresh()
    }
}

enum LabStockError: LocalizedError {
    case invalidQuantity, cameraUnavailable, itemNotRecognized
    var errorDescription: String? {
        switch self {
        case .invalidQuantity: "Enter a valid quantity that does not make stock negative."
        case .cameraUnavailable: "Camera scanning is unavailable on this device."
        case .itemNotRecognized: "This code is not linked to an inventory item."
        }
    }
}
