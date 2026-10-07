import SwiftUI
import UIKit
import VisionKit

enum ScanMode: String, CaseIterable, Identifiable {
    case add = "Add Stock"
    case withdraw = "Withdraw"
    case count = "Stock Count"
    var id: String { rawValue }
}

/// AI-first scanning: one photo → DeepSeek label analysis → confirm → save.
struct ScanView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var mode: ScanMode = .add
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var showingLibrary = false
    @State private var review: ScanReviewContext?
    @State private var isWorking = false
    @State private var message: String?
    @State private var retryImage: UIImage?
    @State private var pendingBarcode: String?

    var body: some View {
        VStack(spacing: 20) {
            Picker("Mode", selection: $mode) { ForEach(ScanMode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(.horizontal)
            if mode == .count {
                InventoryCountFlow()
            } else {
                scanBody
            }
        }
        .navigationTitle("Scan")
        .sheet(isPresented: $showingCamera) { LabelCameraView { image in analyze(image) } }
        .sheet(isPresented: $showingScanner) { BarcodeScannerView { code in showingScanner = false; handleBarcode(code) } }
        .sheet(isPresented: $showingLibrary) { CameraPicker { image in analyze(image) } }
        .sheet(item: $review) { context in
            ScanReviewView(mode: mode, analysis: context.analysis, initialBarcode: context.barcode)
        }
        .overlay { if isWorking { analyzingOverlay } }
        .alert("Scan", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil; retryImage = nil } }
        )) {
            if let image = retryImage {
                Button("Retry") { message = nil; retryImage = nil; analyze(image) }
            }
            Button("Manual entry") {
                message = nil
                retryImage = nil
                review = ScanReviewContext(analysis: nil, barcode: pendingBarcode)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var scanBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: mode == .add ? "camera.viewfinder" : "minus.circle")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text(mode == .add ? "Photograph a reagent label to add stock" : "Photograph a reagent label to withdraw stock")
                .font(.title3.bold()).multilineTextAlignment(.center).padding(.horizontal)
            Text("One photo is enough — REF, LOT and expiry are read automatically.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            Button {
                showingCamera = true
            } label: {
                Label("Photograph Label", systemImage: "camera.fill")
                    .font(.title3.bold()).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 28)

            HStack(spacing: 12) {
                Button { showingScanner = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                    .buttonStyle(.bordered)
                Button { showingLibrary = true } label: { Label("From Photos", systemImage: "photo") }
                    .buttonStyle(.bordered)
            }
            Button("Enter manually") { review = ScanReviewContext(analysis: nil, barcode: nil) }
                .font(.footnote)
            Spacer()
        }
    }

    private var analyzingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing reagent…").font(.headline)
            Text("Reading REF, LOT and expiry from the label")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 12)
    }

    private func analyze(_ image: UIImage) {
        isWorking = true
        message = nil
        pendingBarcode = nil
        Task {
            do {
                let analysis = try await store.analyzeLabel(image)
                // Let the camera sheet finish dismissing before presenting the review.
                try? await Task.sleep(for: .milliseconds(300))
                review = ScanReviewContext(analysis: analysis, barcode: analysis.barcode)
            } catch let error as DeepSeekError {
                retryImage = error.canRetry ? image : nil
                message = error.message
            } catch {
                retryImage = image
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    /// Known barcode: reuse the existing item, the review screen still edits LOT/expiry.
    private func handleBarcode(_ code: String) {
        pendingBarcode = code
        let analysis = ScanAnalysis(
            extraction: ReagentExtraction(),
            nativeBarcode: code,
            localOCRText: nil,
            imageHash: "barcode:\(code)"
        )
        review = ScanReviewContext(analysis: analysis, barcode: code)
    }
}

struct ScanReviewContext: Identifiable {
    let id = UUID()
    let analysis: ScanAnalysis?
    let barcode: String?
}

/// Manual/FEFO batch operation kept for the item detail screen.
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

struct BarcodeScannerView: UIViewControllerRepresentable {
    var continuous = false
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(continuous: continuous, onCode: onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: [
                .ean13, .ean8, .upce, .code128, .code39, .code93,
                .pdf417, .qr, .dataMatrix, .aztec, .codabar
            ])
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
