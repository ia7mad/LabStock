import SwiftUI
import UIKit
import VisionKit

struct InventoryCountFlow: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var selectedGroupID: UUID?
    @State private var sessionID: UUID?
    @State private var counts: [InventoryCount] = []
    @State private var working = false
    @State private var showingScanner = false
    @State private var showingCamera = false
    @State private var showingCompletion = false
    @State private var batchChoices: [InventoryCount] = []
    @State private var choosingBatch = false
    @State private var message: String?

    private var totalExpected: Int { counts.reduce(0) { $0 + $1.expectedQuantity } }
    private var totalCounted: Int { counts.reduce(0) { $0 + $1.countedQuantity } }

    var body: some View {
        Group {
            if let sessionID {
                activeSession(sessionID)
            } else {
                startForm
            }
        }
        .sheet(isPresented: $showingScanner) { BarcodeScannerView(continuous: true) { code in handleScan(code) } }
        .sheet(isPresented: $showingCamera) { LabelCameraView { image in handlePhoto(image) } }
        .overlay { if working { ProgressView("Analyzing reagent…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .alert("Stock Count", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        .confirmationDialog("Complete inventory?", isPresented: $showingCompletion, titleVisibility: .visible) {
            Button("Apply \(abs(totalCounted - totalExpected)) unit difference\(abs(totalCounted - totalExpected) == 1 ? "" : "s")") { complete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Expected \(totalExpected) • Counted \(totalCounted) • Difference \(totalCounted - totalExpected). Stock changes only after confirmation.") }
    }

    private var startForm: some View {
        Form {
            Section("Count Scope") {
                Picker("Inventory", selection: $selectedGroupID) {
                    Text("All inventory").tag(Optional<UUID>.none)
                    ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section {
                Button {
                    working = true
                    Task {
                        do { let result = try await store.startInventory(groupID: selectedGroupID); sessionID = result.0; counts = result.1 }
                        catch { message = error.localizedDescription }
                        working = false
                    }
                } label: { Label("Start Stock Count", systemImage: "list.number") }
                .disabled(working || store.items.isEmpty)
            }
            Section { Text("Scanning increments the selected item's count. You can also adjust each batch directly. Stock is not changed until you review and confirm completion.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func activeSession(_ id: UUID) -> some View {
        VStack(spacing: 0) {
            HStack {
                countSummary("Expected", totalExpected)
                countSummary("Counted", totalCounted)
                countSummary("Difference", totalCounted - totalExpected)
            }.padding(.horizontal)
            List {
                if counts.isEmpty { EmptyStateView(title: "Nothing to count", message: "This scope has no batches yet.", icon: "tray") }
                ForEach(counts) { count in
                    CountRow(count: count, item: store.items.first(where: { $0.id == count.itemId }), batch: store.batches.first(where: { $0.id == count.batchId })) { newValue in
                        update(count, to: newValue)
                    }
                }
            }
            HStack {
                Button {
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable { showingScanner = true }
                    else { message = LabStockError.cameraUnavailable.localizedDescription }
                } label: { Label("Scan", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button {
                    if DataScannerViewController.isSupported {
                        showingCamera = true
                    } else if UIImagePickerController.isSourceTypeAvailable(.camera) || UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                        showingCamera = true
                    } else {
                        message = LabStockError.cameraUnavailable.localizedDescription
                    }
                } label: { Label("Photo", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                Button("Review") { showingCompletion = true }.buttonStyle(.bordered).controlSize(.large)
            }.padding().background(.bar)
        }
        .sheet(isPresented: $choosingBatch) {
            NavigationStack {
                List(batchChoices) { choice in
                    Button {
                        choosingBatch = false
                        increment(choice)
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            if sessionID != nil, DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                                showingScanner = true
                            }
                        }
                    } label: {
                        Text(batchChoiceLabel(choice))
                    }
                }
                .navigationTitle("Select the lot to count")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingBatch = false } } }
            }
        }
    }

    private func batchChoiceLabel(_ count: InventoryCount) -> String {
        let batch = store.batches.first(where: { $0.id == count.batchId })
        let lot = batch?.lotNumber ?? "No lot"
        let expiry = batch?.expiryDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "No expiry"
        return "\(lot) • \(expiry) • Expected \(count.expectedQuantity)"
    }

    private func countSummary(_ label: String, _ value: Int) -> some View {
        VStack { Text("\(value)").font(.title2.bold().monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private func update(_ count: InventoryCount, to quantity: Int) {
        guard let index = counts.firstIndex(where: { $0.id == count.id }) else { return }
        counts[index].countedQuantity = max(0, quantity)
        Task {
            do { counts[index] = try await store.updateCount(count, quantity: quantity) }
            catch { counts[index] = count; message = error.localizedDescription }
        }
    }

    private func handleScan(_ code: String) {
        Task {
            do {
                guard let snapshot = try await store.recognize(code) else { throw LabStockError.itemNotRecognized }
                let candidates = counts.filter { $0.itemId == snapshot.id }
                guard !candidates.isEmpty else { message = "This item is outside the current count scope or has no batch."; return }
                if candidates.count == 1 {
                    increment(candidates[0])
                } else {
                    showingScanner = false
                    try? await Task.sleep(for: .milliseconds(350))
                    batchChoices = candidates
                    choosingBatch = true
                }
            } catch { message = error.localizedDescription }
        }
    }

    private func increment(_ count: InventoryCount) {
        update(count, to: count.countedQuantity + 1)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Photo → AI identification → count the matching batch (LOT/expiry first, then scope).
    private func handlePhoto(_ image: UIImage) {
        working = true
        Task {
            do {
                let analysis = try await store.analyzeLabel(image)
                let matches = await store.matches(for: analysis)
                guard let itemID = matches.first?.item.id else {
                    message = "This item is not in the inventory yet. Add it from the Add Stock tab first."
                    working = false
                    return
                }
                let candidates = counts.filter { $0.itemId == itemID }
                guard !candidates.isEmpty else {
                    message = "This item is outside the current count scope or has no batch."
                    working = false
                    return
                }
                let matchedBatches = Set(BatchMatcher.matches(
                    itemID: itemID,
                    lotNumber: analysis.extraction.lotNumber,
                    expiryDate: analysis.extraction.expiryDate,
                    in: store.batches
                ).map(\.id))
                let preferred = candidates.filter { batch in
                    guard let batchID = batch.batchId else { return false }
                    return matchedBatches.contains(batchID)
                }
                if preferred.count == 1, let only = preferred.first {
                    increment(only)
                } else if candidates.count == 1, let only = candidates.first {
                    increment(only)
                } else {
                    try? await Task.sleep(for: .milliseconds(300))
                    batchChoices = preferred.isEmpty ? candidates : preferred + candidates.filter { !preferred.contains($0) }
                    choosingBatch = true
                }
            } catch let error as DeepSeekError {
                message = error.message
            } catch {
                message = error.localizedDescription
            }
            working = false
        }
    }

    private func complete() {
        guard let sessionID else { return }
        working = true
        Task {
            do { try await store.completeInventory(sessionID: sessionID); self.sessionID = nil; counts = [] }
            catch { message = error.localizedDescription }
            working = false
        }
    }
}

private struct CountRow: View {
    let count: InventoryCount
    let item: StockItem?
    let batch: Batch?
    let onChange: (Int) -> Void
    @State private var directValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item?.name ?? "Unknown item").font(.headline)
                    Text("\(batch?.lotNumber.map { "LOT \($0)" } ?? "No lot") • Expected \(count.expectedQuantity)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(count.countedQuantity)").font(.title2.bold().monospacedDigit())
            }
            HStack {
                Button { onChange(count.countedQuantity - 1) } label: { Image(systemName: "minus.circle.fill") }.disabled(count.countedQuantity == 0)
                Button { onChange(count.countedQuantity + 1) } label: { Image(systemName: "plus.circle.fill") }
                Spacer()
                TextField("Direct count", text: $directValue)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 110)
                Button("Set") { if let value = Int(directValue), value >= 0 { onChange(value); directValue = "" } }
            }.buttonStyle(.borderless)
        }.padding(.vertical, 4)
    }
}
