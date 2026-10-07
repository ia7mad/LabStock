import SwiftUI
import UIKit

/// Fast AI-first confirmation screen: extracted fields, existing-item match and one primary action.
struct ScanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore

    let mode: ScanMode
    let analysis: ScanAnalysis?
    let initialBarcode: String?

    @State private var draft: ScanDraft
    @State private var matches: [ScannedItemMatch] = []
    @State private var selectedItemID: UUID?
    @State private var creatingNew = false
    @State private var batchID: UUID?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var directQuantity = ""

    init(mode: ScanMode, analysis: ScanAnalysis?, initialBarcode: String?) {
        self.mode = mode
        self.analysis = analysis
        self.initialBarcode = initialBarcode
        _draft = State(initialValue: analysis.map { ScanDraft(extraction: $0.extraction, groupID: nil) } ?? ScanDraft())
    }

    private var selectedItem: StockItem? { selectedItemID.flatMap { store.item(withID: $0) } }
    private var itemBatches: [Batch] { selectedItem.map { store.batches(for: $0.id) } ?? [] }
    private var isUsingExisting: Bool { !creatingNew && selectedItem != nil }

    private var canSave: Bool {
        switch mode {
        case .add:
            return creatingNew ? draft.productName.nilIfBlank != nil : selectedItem != nil
        case .withdraw:
            return selectedItem != nil && batchID != nil && draft.quantity > 0
        case .count:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.productName.nilIfBlank ?? (creatingNew ? "New reagent" : "Reagent"))
                            .font(.title3.bold())
                        if let maker = draft.manufacturer.nilIfBlank {
                            Text(maker).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let ref = draft.referenceNumber.nilIfBlank {
                            Text("REF \(ref)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !matches.isEmpty { matchSection }
                fieldsSection
                if mode == .withdraw { batchSection }
                quantitySection
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    save()
                } label: {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(mode == .withdraw ? .red : LabTheme.cyan)
                .disabled(!canSave || isWorking)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryTitle) { save() }.disabled(!canSave || isWorking)
                }
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .task { await loadMatches() }
            .onChange(of: selectedItemID) { _ in selectDefaultBatch() }
            .onChange(of: draft.lotNumber) { _ in selectDefaultBatch() }
            .onChange(of: draft.expiryDate) { _ in selectDefaultBatch() }
        }
    }

    // MARK: Sections

    private var matchSection: some View {
        Section("Possible existing item") {
            ForEach(matches) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.item.name).font(.headline)
                    Text(subtitle(for: entry))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Use Existing") {
                            creatingNew = false
                            selectedItemID = entry.item.id
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUsingExisting && selectedItemID == entry.item.id)
                        Button("Create New") { creatingNew = true; selectedItemID = nil; batchID = nil }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var fieldsSection: some View {
        Section {
            field("Product Name", key: "product_name", text: $draft.productName, disabled: isUsingExisting)
            field("Manufacturer", key: "manufacturer", text: $draft.manufacturer, disabled: isUsingExisting)
            field("REF / Catalog No.", key: "reference_number", text: $draft.referenceNumber, disabled: isUsingExisting)
            field("LOT", key: "lot_number", text: $draft.lotNumber)
            Toggle("Has expiry date", isOn: Binding(
                get: { draft.expiryDate != nil },
                set: { draft.expiryDate = $0 ? (draft.expiryDate ?? Date()) : nil }
            ))
            if draft.expiryDate != nil {
                DatePicker("Expiry", selection: Binding(
                    get: { draft.expiryDate ?? Date() },
                    set: { draft.expiryDate = $0 }
                ), displayedComponents: .date)
                .overlay(alignment: .trailing) { lowConfidenceDot("expiry_date") }
            }
            field("Volume / Pack", key: "volume", text: $draft.volume)
            field("Storage", key: "storage_temperature", text: $draft.storageTemperature)
            if let barcode = initialBarcode?.nilIfBlank {
                LabeledContent("Barcode", value: barcode)
            }
            Picker("Group", selection: $draft.groupID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
            }
        } header: {
            HStack {
                Text(isUsingExisting ? "Using Existing Item" : "Reagent Details")
                if analysis?.extraction.isLowConfidence == true {
                    Spacer()
                    Label("Low confidence", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        } footer: {
            if isUsingExisting {
                Text("Existing item selected. LOT and expiry update the batch for this box.")
                    .font(.footnote)
            } else if analysis != nil {
                Text("Nothing is saved until you confirm.").font(.footnote)
            }
        }
    }

    @ViewBuilder private var batchSection: some View {
        Section("Lot") {
            if itemBatches.isEmpty {
                Text(selectedItem == nil ? "Select an item first." : "No batches yet for this item.")
                    .foregroundStyle(.secondary)
            } else if itemBatches.count == 1, let only = itemBatches.first {
                Text("LOT \(only.lotNumber ?? "—") • Qty \(only.currentQuantity)")
            } else {
                Picker("Batch", selection: $batchID) {
                    ForEach(itemBatches) { batch in
                        Text(batchLabel(batch)).tag(Optional(batch.id))
                    }
                }
            }
        }
    }

    private var quantitySection: some View {
        Section("Quantity") {
            HStack {
                Button {
                    draft.quantity = max(1, draft.quantity - 1)
                } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(draft.quantity <= 1)
                Text("\(draft.quantity)")
                    .font(.title2.monospacedDigit())
                    .frame(maxWidth: .infinity)
                Button {
                    draft.quantity += 1
                } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
            }
            TextField("Direct quantity", text: $directQuantity)
                .keyboardType(.numberPad)
                .onSubmit {
                    if let value = Int(directQuantity), value > 0 { draft.quantity = value }
                    directQuantity = ""
                }
        }
    }

    private func field(_ title: String, key: String, text: Binding<String>, disabled: Bool = false) -> some View {
        HStack {
            TextField(title, text: text)
                .disabled(disabled)
                .autocorrectionDisabled()
            lowConfidenceDot(key)
        }
    }

    @ViewBuilder private func lowConfidenceDot(_ key: String) -> some View {
        if let confidence = analysis?.extraction.fieldConfidence(for: key), confidence < 0.5 {
            Circle().fill(.orange).frame(width: 7, height: 7)
                .accessibilityLabel("Low confidence")
        }
    }

    // MARK: Actions

    private func subtitle(for entry: ScannedItemMatch) -> String {
        let item = entry.item
        let group = item.groupId.flatMap { id in store.groups.first(where: { $0.id == id })?.name } ?? "Ungrouped"
        return [entry.match.kind.label, item.manufacturer, item.referenceNumber.map { "REF \($0)" }, group]
            .compactMap { $0 }.joined(separator: " • ")
    }

    private func batchLabel(_ batch: Batch) -> String {
        let lot = batch.lotNumber ?? "No lot"
        let expiry = batch.expiryDate?.formatted(date: .numeric, time: .omitted) ?? "No expiry"
        return "\(lot) • \(expiry) • Qty \(batch.currentQuantity)"
    }

    private func loadMatches() async {
        guard !didLoad else { return }
        didLoad = true
        if draft.groupID == nil { draft.groupID = store.groups.first?.id }
        guard let analysis else { creatingNew = true; return }
        matches = await store.matches(for: analysis)
        if let first = matches.first {
            creatingNew = false
            selectedItemID = first.item.id
        } else {
            creatingNew = true
        }
        selectDefaultBatch()
    }

    private func selectDefaultBatch() {
        guard mode == .withdraw, let selectedItemID else { batchID = nil; return }
        let batches = store.batches(for: selectedItemID)
        guard !batches.isEmpty else { batchID = nil; return }
        let matched = BatchMatcher.matches(
            itemID: selectedItemID,
            lotNumber: draft.lotNumber,
            expiryDate: draft.expiryDate,
            in: batches
        )
        if matched.count == 1 {
            batchID = matched.first?.id
        } else if matched.isEmpty {
            batchID = InventoryRules.preferredFEFOBatch(from: batches)?.id
        } else {
            batchID = InventoryRules.preferredFEFOBatch(from: matched)?.id ?? matched.first?.id
        }
    }

    private func save() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .add:
                    let itemID: UUID
                    if creatingNew {
                        itemID = try await store.createItem(with: draft, analysis: analysis).id
                    } else if let selectedItemID {
                        itemID = selectedItemID
                        await store.learnAliases(itemID: itemID, draft: draft, analysis: analysis)
                    } else {
                        throw LabStockError.itemNotRecognized
                    }
                    try await store.addStock(
                        itemID: itemID,
                        lot: draft.lotNumber.nilIfBlank,
                        expiry: draft.expiryDate,
                        quantity: draft.quantity,
                        note: nil
                    )
                case .withdraw:
                    guard let batchID else { throw LabStockError.noBatchSelected }
                    try await store.withdrawStock(batchID: batchID, quantity: draft.quantity, note: nil)
                case .count:
                    break
                }
                dismiss()
            } catch let error as DeepSeekError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: "Add to Stock"
        case .withdraw: "Withdraw"
        case .count: "Count Item"
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .add: "Add to Stock"
        case .withdraw: "Withdraw"
        case .count: "Count Item"
        }
    }
}
