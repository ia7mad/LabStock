import SwiftUI

enum ExportReport: String, CaseIterable, Identifiable {
    case inventoryCSV = "Inventory CSV"
    case inventoryPDF = "Inventory PDF"
    case historyCSV = "Movement History CSV"
    var id: String { rawValue }
}

/// Inventory + history exports with scope selection and the native share sheet.
struct ExportView: View {
    var initialReport: ExportReport? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30

    @State private var scope: ExportScope = .all
    @State private var groupID: UUID?
    @State private var shareItems: [Any] = []
    @State private var isSharing = false
    @State private var errorMessage: String?
    @State private var didRunInitial = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    Picker("Scope", selection: $scope) {
                        ForEach(ExportScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if scope == .group {
                        Picker("Group", selection: $groupID) {
                            Text("Choose a group").tag(Optional<UUID>.none)
                            ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                Section("Reports") {
                    ForEach(ExportReport.allCases) { report in
                        Button { run(report) } label: { Label(report.rawValue, systemImage: symbol(for: report)) }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Text("Files open cleanly in Excel, Numbers and Google Sheets. Share to Files, AirDrop, WhatsApp or Email.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Export Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $isSharing) { ShareSheet(items: shareItems) }
            .task {
                guard !didRunInitial, let initialReport else { return }
                didRunInitial = true
                run(initialReport)
            }
        }
    }

    private func symbol(for report: ExportReport) -> String {
        switch report {
        case .inventoryCSV: "tablecells"
        case .inventoryPDF: "doc.richtext"
        case .historyCSV: "clock.arrow.circlepath"
        }
    }

    private func run(_ report: ExportReport) {
        switch report {
        case .inventoryCSV: exportInventoryCSV()
        case .inventoryPDF: exportInventoryPDF()
        case .historyCSV: exportHistoryCSV()
        }
    }

    private var rows: [InventoryExportRow] {
        InventoryExport.rows(
            snapshots: store.snapshots,
            groups: store.groups,
            scope: scope,
            groupID: groupID,
            warningDays: warningDays
        )
    }

    private func exportInventoryCSV() {
        errorMessage = nil
        let exportRows = rows
        guard !exportRows.isEmpty else { errorMessage = "There is nothing to export for this scope."; return }
        let csv = InventoryExport.inventoryCSV(rows: exportRows, summary: InventoryExport.summary(forRows: exportRows))
        let name = InventoryExport.fileName(prefix: "LabStock_Inventory") + ".csv"
        guard let url = InventoryExport.writeTemporaryFile(named: name, text: csv) else {
            errorMessage = "Could not create the export file."
            return
        }
        present([url])
    }

    private func exportInventoryPDF() {
        errorMessage = nil
        let exportRows = rows
        guard !exportRows.isEmpty else { errorMessage = "There is nothing to export for this scope."; return }
        let pdf = PDFReportBuilder.inventoryReport(rows: exportRows, summary: InventoryExport.summary(forRows: exportRows))
        let name = InventoryExport.fileName(prefix: "LabStock_Inventory") + ".pdf"
        guard let url = InventoryExport.writeTemporaryFile(named: name, contents: pdf) else {
            errorMessage = "Could not create the export file."
            return
        }
        present([url])
    }

    private func exportHistoryCSV() {
        errorMessage = nil
        guard !store.movements.isEmpty else { errorMessage = "There is no movement history yet."; return }
        let csv = InventoryExport.movementsCSV(
            movements: store.movements,
            itemName: { store.item(withID: $0)?.name ?? "Unknown item" },
            userName: { store.displayName(for: $0) }
        )
        let name = InventoryExport.fileName(prefix: "LabStock_History") + ".csv"
        guard let url = InventoryExport.writeTemporaryFile(named: name, text: csv) else {
            errorMessage = "Could not create the export file."
            return
        }
        present([url])
    }

    private func present(_ items: [Any]) {
        shareItems = items
        isSharing = true
    }
}
