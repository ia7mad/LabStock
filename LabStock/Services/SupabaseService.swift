import Foundation
import Supabase

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    private init() {
        let options = SupabaseClientOptions(
            db: .init(encoder: .labStock, decoder: .labStock),
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: options
        )
    }

    func currentUserID() async -> UUID? { try? await client.auth.session.user.id }

    func signIn(email: String, password: String) async throws -> UUID {
        try await client.auth.signIn(email: email, password: password).user.id
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> UUID? {
        let metadata: [String: AnyJSON]? = displayName?.nilIfBlank.map { ["display_name": .string($0)] }
        return try await client.auth.signUp(email: email, password: password, data: metadata).session?.user.id
    }

    func signOut() async throws {
        stopRealtime()
        try await client.auth.signOut()
    }

    func fetchGroups() async throws -> [InventoryGroup] {
        try await client.from("groups").select().order("name").execute().value
    }

    func fetchProfiles() async throws -> [Profile] {
        try await client.from("profiles").select().order("display_name").execute().value
    }

    func updateProfile(userID: UUID, warningDays: Int, notificationsEnabled: Bool) async throws {
        try await client.from("profiles").update(UpdateProfilePayload(
            expiryWarningDays: warningDays,
            notificationsEnabled: notificationsEnabled
        )).eq("id", value: userID).execute()
    }

    func createGroup(name: String, userID: UUID) async throws -> InventoryGroup {
        try await client.from("groups")
            .insert(NewGroupPayload(name: name, createdBy: userID))
            .select().single().execute().value
    }

    func renameGroup(id: UUID, name: String) async throws {
        try await client.from("groups").update(UpdateGroupPayload(name: name)).eq("id", value: id).execute()
    }

    func deleteGroup(id: UUID) async throws {
        try await client.from("groups").delete().eq("id", value: id).execute()
    }

    func fetchItems() async throws -> [StockItem] {
        try await client.from("items").select().order("name").execute().value
    }

    func createItem(_ payload: NewItemPayload) async throws -> StockItem {
        try await client.from("items").insert(payload).select().single().execute().value
    }

    func createAlias(itemID: UUID, type: AliasType, value: String) async throws {
        let userID = try await client.auth.session.user.id
        try await client.from("scan_aliases").insert(NewAliasPayload(
            itemId: itemID, type: type, value: value, createdBy: userID
        )).execute()
    }

    /// Looks up items by decoded barcode / REF / catalog values.
    func itemIDs(forAliasValues values: [String]) async throws -> [UUID] {
        let normalized = Array(Set(values.compactMap { $0.nilIfBlank?.lowercased() }))
        guard !normalized.isEmpty else { return [] }
        let aliases: [ScanAlias] = try await client.from("scan_aliases").select()
            .in("normalized_value", values: normalized).execute().value
        var seen = Set<UUID>()
        return aliases.map(\.itemId).filter { seen.insert($0).inserted }
    }

    /// Best-effort alias learning; duplicates are ignored.
    func addAliases(itemID: UUID, type: AliasType, values: [String]) async {
        let userID = try? await client.auth.session.user.id
        guard let userID else { return }
        let payloads = Array(Set(values.compactMap { $0.nilIfBlank }))
            .map { NewAliasPayload(itemId: itemID, type: type, value: $0, createdBy: userID) }
        guard !payloads.isEmpty else { return }
        _ = try? await client.from("scan_aliases").insert(payloads).execute()
    }

    func batches(forItem itemID: UUID) async throws -> [Batch] {
        try await client.from("batches").select().eq("item_id", value: itemID)
            .order("expiry_date", ascending: true, nullsFirst: false).execute().value
    }

    /// Reuses the exact batch (item + LOT + expiry) or creates an empty one.
    func findOrCreateBatch(itemID: UUID, lotNumber: String?, expiryDate: Date?) async throws -> Batch {
        let existing = try await batches(forItem: itemID)
        if let match = BatchMatcher.matches(itemID: itemID, lotNumber: lotNumber, expiryDate: expiryDate, in: existing).first {
            return match
        }
        return try await createBatch(itemID: itemID, lot: lotNumber, expiry: expiryDate)
    }

    func createItem(name: String, manufacturer: String?, referenceNumber: String?, groupID: UUID?, unitName: String, lowStockThreshold: Int) async throws -> StockItem {
        let userID = try await client.auth.session.user.id
        return try await client.from("items").insert(NewItemPayload(
            groupId: groupID,
            name: name,
            manufacturer: manufacturer?.nilIfBlank,
            referenceNumber: referenceNumber?.nilIfBlank,
            notes: nil,
            lowStockThreshold: max(0, lowStockThreshold),
            unitName: unitName.nilIfBlank ?? "unit",
            createdBy: userID
        )).select().single().execute().value
    }

    func fetchBatches() async throws -> [Batch] {
        try await client.from("batches").select().order("expiry_date", ascending: true, nullsFirst: false).execute().value
    }

    func createBatch(itemID: UUID, lot: String?, expiry: Date?) async throws -> Batch {
        let userID = try await client.auth.session.user.id
        let payload = NewBatchPayload(
            itemId: itemID,
            lotNumber: lot?.nilIfBlank,
            expiryDate: expiry.map { DateFormatter.sqlDate.string(from: $0) },
            createdBy: userID
        )
        return try await client.from("batches").insert(payload).select().single().execute().value
    }

    func fetchMovements(limit: Int = 250) async throws -> [StockMovement] {
        try await client.from("stock_movements").select()
            .order("created_at", ascending: false).limit(limit).execute().value
    }

    func recognize(alias rawValue: String) async throws -> StockItem? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var aliases: [ScanAlias] = try await client.from("scan_aliases").select()
            .eq("type", value: AliasType.barcode.rawValue).eq("normalized_value", value: value).limit(1).execute().value
        if aliases.isEmpty {
            aliases = try await client.from("scan_aliases").select()
                .eq("type", value: AliasType.ref.rawValue).eq("normalized_value", value: value).limit(1).execute().value
        }
        guard let alias = aliases.first else { return nil }
        let items: [StockItem] = try await client.from("items").select()
            .eq("id", value: alias.itemId).limit(1).execute().value
        return items.first
    }

    func applyStock(batchID: UUID, delta: Int, type: MovementType, note: String? = nil, allowNegative: Bool = false) async throws {
        struct Params: Encodable {
            let pBatchId: UUID
            let pDelta: Int
            let pType: String
            let pNote: String?
            let pAllowNegative: Bool
        }
        try await client.rpc("apply_stock_delta", params: Params(
            pBatchId: batchID,
            pDelta: delta,
            pType: type.rawValue,
            pNote: note?.nilIfBlank,
            pAllowNegative: allowNegative
        )).execute()
    }

    struct CreatedScanRecord: Decodable { let itemId: UUID; let batchId: UUID }

    func createScannedItem(fields: OCRFields, groupID: UUID?, barcode: String?, quantity: Int) async throws -> CreatedScanRecord {
        let userID = try await client.auth.session.user.id
        let item: StockItem = try await client.from("items").insert(NewItemPayload(
            groupId: groupID,
            name: fields.name,
            manufacturer: fields.manufacturer.nilIfBlank,
            referenceNumber: fields.referenceNumber.nilIfBlank,
            notes: nil,
            lowStockThreshold: 1,
            unitName: "unit",
            createdBy: userID
        )).select().single().execute().value
        let batch = try await createBatch(itemID: item.id, lot: fields.lotNumber, expiry: fields.expiryDate)
        var aliases: [NewAliasPayload] = []
        if let barcode = barcode?.nilIfBlank {
            aliases.append(NewAliasPayload(itemId: item.id, type: .barcode, value: barcode, createdBy: userID))
        }
        if let reference = fields.referenceNumber.nilIfBlank {
            aliases.append(NewAliasPayload(itemId: item.id, type: .ref, value: reference, createdBy: userID))
        }
        if !aliases.isEmpty { try await client.from("scan_aliases").insert(aliases).execute() }
        try await applyStock(batchID: batch.id, delta: quantity, type: .add, note: "Initial scanned stock")
        return CreatedScanRecord(itemId: item.id, batchId: batch.id)
    }

    func startInventory(groupID: UUID?) async throws -> UUID {
        let userID = try await client.auth.session.user.id
        let session: InventorySession = try await client.from("inventory_sessions")
            .insert(NewSessionPayload(groupId: groupID, startedBy: userID))
            .select().single().execute().value
        async let allItems = fetchItems()
        async let allBatches = fetchBatches()
        let items = try await allItems
        let batches = try await allBatches
        let itemIDs = Set(items.filter { groupID == nil || $0.groupId == groupID }.map(\.id))
        let payloads = batches.filter { itemIDs.contains($0.itemId) }.map {
            NewCountPayload(sessionId: session.id, itemId: $0.itemId, batchId: $0.id, expectedQuantity: $0.currentQuantity)
        }
        if !payloads.isEmpty { try await client.from("inventory_counts").insert(payloads).execute() }
        return session.id
    }

    func fetchCounts(sessionID: UUID) async throws -> [InventoryCount] {
        try await client.from("inventory_counts").select()
            .eq("session_id", value: sessionID).order("created_at").execute().value
    }

    func setCount(_ count: InventoryCount, quantity: Int) async throws {
        try await client.from("inventory_counts")
            .update(UpdateCountPayload(countedQuantity: max(0, quantity)))
            .eq("id", value: count.id).execute()
    }

    func completeInventory(sessionID: UUID) async throws {
        struct Params: Encodable { let pSessionId: UUID }
        try await client.rpc("complete_inventory_session", params: Params(pSessionId: sessionID)).execute()
    }

    func startRealtime(onChange: @escaping @MainActor () async -> Void) async throws {
        stopRealtime()
        let channel = client.channel("labstock-inventory")
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        try await channel.subscribeWithError()
        realtimeChannel = channel
        realtimeTask = Task { @MainActor in
            for await _ in changes { await onChange() }
        }
    }

    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = realtimeChannel {
            Task { await client.removeChannel(channel) }
        }
        realtimeChannel = nil
    }
}
