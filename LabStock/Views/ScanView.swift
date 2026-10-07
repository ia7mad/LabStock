import SwiftUI
import UIKit
import VisionKit

enum ScanMode: String, CaseIterable, Identifiable {
    case add = "Add Stock"
    case withdraw = "Withdraw"
    case count = "Stock Count"
    var id: String { rawValue }
}

struct ScanView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var mode: ScanMode = .add
    @State private var showingScanner = false
    @State private var scannedCode: String?
    @State private var recognized: ItemSnapshot?
    @State private var unknownCode: String?
    @State private var showingCamera = false
    @State private var ocrFields: OCRFields?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $mode) { ForEach(ScanMode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
            if mode == .count {
                InventoryCountFlow()
            } else {
                Spacer()
                Image(systemName: mode == .add ? "plus.viewfinder" : "minus.viewfinder")
                    .font(.system(size: 72)).foregroundStyle(.tint)
                Text(mode == .add ? "Scan a reagent to add stock" : "Scan a reagent to withdraw stock")
                    .font(.title3.bold()).multilineTextAlignment(.center)
                Button {
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable { showingScanner = true }
                    else { message = LabStockError.cameraUnavailable.localizedDescription }
                } label: {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder").font(.title3.bold()).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 28)
                Button("Capture Label with OCR") { unknownCode = nil; showingCamera = true }
                    .buttonStyle(.bordered)
                Spacer()
            }
        }
        .navigationTitle("Scan")
        .sheet(isPresented: $showingScanner) { BarcodeScannerView { code in showingScanner = false; handle(code) } }
        .sheet(isPresented: $showingCamera) { CameraPicker { image in process(image) } }
        .sheet(item: $recognized) { snapshot in StockOperationView(snapshot: snapshot, mode: mode) }
        .sheet(item: $ocrFields) { fields in OCRConfirmationView(initial: fields, barcode: unknownCode) }
        .overlay { if isWorking { ProgressView("Recognizing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .alert("Scan Result", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            if unknownCode != nil { Button("Capture Label") { showingCamera = true } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func handle(_ code: String) {
        scannedCode = code; isWorking = true
        Task {
            do {
                let match = try await store.recognize(code)
                if let snapshot = match {
                    recognized = snapshot
                } else {
                    unknownCode = code
                    message = "Unknown barcode. Capture the label so the extracted fields can be confirmed."
                }
            } catch { message = error.localizedDescription }
            isWorking = false
        }
    }

    private func process(_ image: UIImage) {
        showingCamera = false; isWorking = true
        Task {
            do { ocrFields = try await OCRService.recognize(image: image) }
            catch { message = error.localizedDescription }
            isWorking = false
        }
    }
}

struct StockOperationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let snapshot: ItemSnapshot
    let mode: ScanMode
    @State private var batchID: UUID?
    @State private var createNewBatch = false
    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var quantity = 1
    @State private var note = ""
    @State private var saving = false
    @State private var error: String?

    private var selectedBatch: Batch? { snapshot.batches.first(where: { $0.id == batchID }) }
    private var canSave: Bool {
        quantity > 0 && (mode == .add || (selectedBatch?.currentQuantity ?? 0) >= quantity)
            && (mode != .withdraw || batchID != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(snapshot.item.name) {
                    if !snapshot.batches.isEmpty {
                        Picker("Batch", selection: $batchID) {
                            ForEach(snapshot.batches) { batch in
                                Text(batchLabel(batch)).tag(Optional(batch.id))
                            }
                        }
                    }
                    if mode == .add {
                        Toggle("Create a new batch", isOn: $createNewBatch)
                        if createNewBatch || snapshot.batches.isEmpty {
                            TextField("LOT (optional)", text: $lot).textInputAutocapitalization(.characters)
                            Toggle("Has expiry date", isOn: $hasExpiry)
                            if hasExpiry { DatePicker("Expiry", selection: $expiry, displayedComponents: .date) }
                        }
                    }
                }
                Section("Quantity") {
                    Stepper(value: $quantity, in: 1...9999) { Text("\(quantity)").font(.title2.monospacedDigit()) }
                    TextField("Quantity", value: $quantity, format: .number).keyboardType(.numberPad)
                    TextField("Note (optional)", text: $note)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(mode.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave || saving) }
            }
            .onAppear {
                if mode == .withdraw { batchID = InventoryRules.preferredFEFOBatch(from: snapshot.batches)?.id }
                else { batchID = snapshot.batches.first?.id; createNewBatch = snapshot.batches.isEmpty }
            }
        }
    }

    private func batchLabel(_ batch: Batch) -> String {
        let lot = batch.lotNumber ?? "No lot"
        let expiry = batch.expiryDate?.formatted(date: .numeric, time: .omitted) ?? "No expiry"
        return "\(lot) • \(expiry) • Qty \(batch.currentQuantity)"
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                let useNew = mode == .add && (createNewBatch || snapshot.batches.isEmpty)
                try await store.applyStock(
                    itemID: snapshot.id, batchID: useNew ? nil : batchID,
                    newLot: useNew ? lot : nil, newExpiry: useNew && hasExpiry ? expiry : nil,
                    delta: mode == .withdraw ? -quantity : quantity,
                    type: mode == .withdraw ? .withdraw : .add, note: note
                )
                dismiss()
            } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

private struct OCRConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let barcode: String?
    @State private var fields: OCRFields
    @State private var groupID: UUID?
    @State private var quantity = 1
    @State private var hasExpiry: Bool
    @State private var saving = false
    @State private var error: String?

    init(initial: OCRFields, barcode: String?) {
        self.barcode = barcode
        _fields = State(initialValue: initial)
        _hasExpiry = State(initialValue: initial.expiryDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm Extracted Fields") {
                    TextField("Reagent name", text: $fields.name)
                    TextField("Manufacturer", text: $fields.manufacturer)
                    TextField("REF", text: $fields.referenceNumber).textInputAutocapitalization(.characters)
                    TextField("LOT", text: $fields.lotNumber).textInputAutocapitalization(.characters)
                    Toggle("Has expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expiry", selection: Binding(get: { fields.expiryDate ?? .now }, set: { fields.expiryDate = $0 }), displayedComponents: .date)
                    }
                }
                Section("Inventory") {
                    Picker("Group", selection: $groupID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }
                Section { Text("Nothing is saved until you tap Save. The barcode and REF become aliases for faster future scans.").font(.footnote).foregroundStyle(.secondary) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Confirm Label")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(fields.name.nilIfBlank == nil || saving) }
            }
            .onChange(of: hasExpiry) { if !$0 { fields.expiryDate = nil } }
        }
    }

    private func save() {
        saving = true; error = nil
        Task {
            do { try await store.createScanned(fields: fields, groupID: groupID, barcode: barcode, quantity: quantity); dismiss() }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    var continuous = false
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(continuous: continuous, onCode: onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .qr, .dataMatrix])
        ]
        let controller = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let continuous: Bool
        let onCode: (String) -> Void
        private var delivered = false
        init(continuous: Bool, onCode: @escaping (String) -> Void) { self.continuous = continuous; self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let code = barcode.payloadStringValue {
                    delivered = true; onCode(code)
                    if continuous { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.delivered = false } }
                    return
                }
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

extension OCRFields: Identifiable { var id: String { "\(name)|\(referenceNumber)|\(lotNumber)" } }
