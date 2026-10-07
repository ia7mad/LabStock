import SwiftUI

struct ItemDetailView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    let snapshot: ItemSnapshot

    @State private var operation: ScanMode?
    @State private var showingAdjust = false
    @State private var showingEdit = false
    @State private var editingBatch: Batch?

    private var current: ItemSnapshot {
        store.snapshots.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    private var status: ExportStatus { current.status(warningDays: warningDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                actions
                batchesSection
                historySection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(current.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingEdit = true } label: { Label("Edit Item", systemImage: "pencil") }
                    Button { showingAdjust = true } label: { Label("Adjust Stock", systemImage: "slider.horizontal.3") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $operation) { mode in StockOperationView(snapshot: current, mode: mode) }
        .sheet(isPresented: $showingAdjust) { AdjustStockView(snapshot: current) }
        .sheet(isPresented: $showingEdit) { EditItemView(snapshot: current) }
        .sheet(item: $editingBatch) { batch in EditBatchView(batch: batch, itemName: current.item.name) }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.item.name).font(.title3.bold())
                    if let maker = current.item.manufacturer {
                        Text(maker).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let ref = current.item.referenceNumber {
                        Text("REF \(ref)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusBadge(text: status.rawValue, color: status.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL STOCK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(current.totalQuantity)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(current.batches.count) batch\(current.batches.count == 1 ? "" : "es") • low stock at \(current.item.lowStockThreshold)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let notes = current.item.notes?.nilIfBlank {
                Text(notes).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actionButton("Add", "plus.circle.fill", LabTheme.teal) { operation = .add }
            actionButton("Withdraw", "minus.circle.fill", .red) { operation = .withdraw }
            actionButton("Adjust", "slider.horizontal.3", LabTheme.amber) { showingAdjust = true }
            actionButton("Edit", "pencil", LabTheme.cyan) { showingEdit = true }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private var batchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batches").font(.headline)
            if current.batches.isEmpty {
                EmptyStateView(title: "No batches", message: "Add stock to create the first batch.", icon: "shippingbox")
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            }
            ForEach(current.batches) { batch in
                BatchCard(batch: batch, warningDays: warningDays, unitName: current.item.unitName) {
                    editingBatch = batch
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent History").font(.headline)
            let history = Array(store.stockHistory(for: current.id).prefix(10))
            if history.isEmpty {
                EmptyStateView(title: "No movements", message: "Stock activity for this item will appear here.", icon: "clock")
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(history) { movement in
                        MovementRow(movement: movement)
                        if movement.id != history.last?.id { Divider() }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            }
        }
    }
}

struct BatchCard: View {
    let batch: Batch
    let warningDays: Int
    let unitName: String
    let onEdit: () -> Void

    private var status: ExpiryStatus {
        InventoryRules.expiryStatus(for: batch.expiryDate, warningDays: warningDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.lotNumber.map { "LOT \($0)" } ?? "No lot")
                        .font(.subheadline.weight(.semibold))
                    Text(batch.expiryDate.map { "EXP \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No expiry")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(batch.currentQuantity)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(unitName).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if status == .expired { StatusBadge(text: "EXPIRED", color: .red) }
                else if status == .expiringSoon { StatusBadge(text: "EXPIRING", color: .orange) }
                Spacer()
                Button { onEdit() } label: { Label("Edit LOT", systemImage: "pencil") }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let snapshot: ItemSnapshot

    @State private var name = ""
    @State private var manufacturer = ""
    @State private var reference = ""
    @State private var groupID: UUID?
    @State private var unitName = "unit"
    @State private var lowStockThreshold = 1
    @State private var notes = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Reagent") {
                    TextField("Item name", text: $name)
                    TextField("Manufacturer", text: $manufacturer)
                    TextField("REF / Catalog No.", text: $reference).textInputAutocapitalization(.characters)
                    Picker("Group", selection: $groupID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("Stock rules") {
                    TextField("Unit", text: $unitName)
                    Stepper("Low stock at \(lowStockThreshold)", value: $lowStockThreshold, in: 0...999)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Item", systemImage: "trash") }
                        .disabled(!store.canDelete(snapshot.item))
                    if !store.canDelete(snapshot.item) {
                        Text("Deletion is blocked because this item has stock history. Adjust quantities to zero instead — audit history is never deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.nilIfBlank == nil || saving) }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only works when the item has no stock history.")
            }
        }
    }

    private func load() {
        name = snapshot.item.name
        manufacturer = snapshot.item.manufacturer ?? ""
        reference = snapshot.item.referenceNumber ?? ""
        groupID = snapshot.item.groupId
        unitName = snapshot.item.unitName
        lowStockThreshold = snapshot.item.lowStockThreshold
        notes = snapshot.item.notes ?? ""
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            do {
                try await store.updateItem(
                    snapshot.item,
                    name: name,
                    manufacturer: manufacturer,
                    referenceNumber: reference,
                    groupID: groupID,
                    unitName: unitName,
                    lowStockThreshold: lowStockThreshold,
                    notes: notes
                )
                dismiss()
            } catch { errorMessage = error.localizedDescription }
            saving = false
        }
    }

    private func delete() {
        saving = true
        errorMessage = nil
        Task {
            do {
                try await store.deleteItem(snapshot.item)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
            saving = false
        }
    }
}

struct EditBatchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let batch: Batch
    let itemName: String

    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(itemName) {
                    TextField("LOT number", text: $lot).textInputAutocapitalization(.characters)
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("Expiry", selection: $expiry, displayedComponents: .date) }
                }
                Section {
                    Text("Quantity is not edited here — use Add, Withdraw or Adjust so stock history stays accurate.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Edit Batch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving) }
            }
            .onAppear {
                lot = batch.lotNumber ?? ""
                hasExpiry = batch.expiryDate != nil
                expiry = batch.expiryDate ?? Date()
            }
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            do {
                try await store.updateBatch(batch, lotNumber: lot, expiryDate: hasExpiry ? expiry : nil)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
            saving = false
        }
    }
}

/// "System says 10, actual is 8" → apply_stock_delta(type: adjustment, delta: -2).
struct AdjustStockView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let snapshot: ItemSnapshot

    @State private var batchID: UUID?
    @State private var actual = 0
    @State private var note = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var selectedBatch: Batch? {
        let batches = store.batches(for: snapshot.id)
        return batches.first(where: { $0.id == batchID }) ?? batches.first
    }

    private var current: Int { selectedBatch?.currentQuantity ?? 0 }
    private var delta: Int { InventoryRules.adjustmentDelta(current: current, actual: actual) }

    var body: some View {
        NavigationStack {
            Form {
                if store.batches(for: snapshot.id).count > 1 {
                    Section("Batch") {
                        Picker("Batch", selection: $batchID) {
                            ForEach(store.batches(for: snapshot.id)) { batch in
                                Text("\(batch.lotNumber ?? "No lot") • Qty \(batch.currentQuantity)")
                                    .tag(Optional(batch.id))
                            }
                        }
                    }
                }
                Section("Quantity") {
                    LabeledContent("Current quantity", value: "\(current)")
                    HStack {
                        Button { actual = max(0, actual - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .disabled(actual <= 0)
                        Text("\(actual)")
                            .font(.title2.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .contentTransition(.numericText())
                        Button { actual += 1 } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                    }
                    LabeledContent("Difference") {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .foregroundStyle(delta == 0 ? Color.secondary : (delta > 0 ? Color.green : Color.red))
                            .font(.headline.monospacedDigit())
                    }
                    TextField("Reason (recommended)", text: $note, axis: .vertical)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Adjust Stock")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { save() }
                        .disabled(saving || !InventoryRules.isValidAdjustment(delta: delta) || selectedBatch == nil)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                batchID = store.batches(for: snapshot.id).first?.id
                actual = current
            }
            .onChange(of: batchID) { _ in actual = current }
        }
    }

    private func save() {
        guard let batch = selectedBatch else { return }
        saving = true
        errorMessage = nil
        Task {
            do {
                try await store.adjustStock(batchID: batch.id, current: batch.currentQuantity, actualQuantity: actual, note: note)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
            saving = false
        }
    }
}
