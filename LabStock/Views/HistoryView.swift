import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var groupID: UUID?
    @State private var itemID: UUID?
    @State private var movementType: MovementType?
    @State private var userID: UUID?
    @State private var dateRange = HistoryDateRange.all
    @State private var showingFilters = false
    @State private var exportReport: ExportReport?

    private var filtered: [StockMovement] {
        store.movements.filter { movement in
            let item = store.item(withID: movement.itemId)
            let groupMatches = groupID == nil || item?.groupId == groupID
            let itemMatches = itemID == nil || movement.itemId == itemID
            let typeMatches = movementType == nil || movement.type == movementType
            let userMatches = userID == nil || movement.userId == userID
            let dateMatches = dateRange.startDate.map { movement.createdAt >= $0 } ?? true
            return groupMatches && itemMatches && typeMatches && userMatches && dateMatches
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                EmptyStateView(title: "No movements", message: "Stock activity will appear here as you scan and adjust.", icon: "clock")
                    .listRowBackground(Color.clear)
            }
            ForEach(filtered) { MovementRow(movement: $0) }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingFilters = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }
                    Button { exportReport = .historyCSV } label: { Label("Export History CSV", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                Form {
                    Picker("Group", selection: $groupID) {
                        Text("All").tag(Optional<UUID>.none)
                        ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Item", selection: $itemID) {
                        Text("All").tag(Optional<UUID>.none)
                        ForEach(store.items) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Movement", selection: $movementType) {
                        Text("All").tag(Optional<MovementType>.none)
                        ForEach(MovementType.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    Picker("User", selection: $userID) {
                        Text("All").tag(Optional<UUID>.none)
                        ForEach(Array(Set(store.movements.map(\.userId))), id: \.self) { id in
                            Text(store.displayName(for: id)).tag(Optional(id))
                        }
                    }
                    Picker("Date", selection: $dateRange) { ForEach(HistoryDateRange.allCases) { Text($0.rawValue).tag($0) } }
                }
                .navigationTitle("History Filters")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") { groupID = nil; itemID = nil; movementType = nil; userID = nil; dateRange = .all }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } }
                }
            }
        }
        .sheet(item: $exportReport) { report in ExportView(initialReport: report) }
        .refreshable { await store.refresh() }
    }
}

struct MovementRow: View {
    @EnvironmentObject private var store: InventoryStore
    let movement: StockMovement

    private var itemName: String { store.item(withID: movement.itemId)?.name ?? "Unknown item" }

    private var detail: String {
        [
            movement.lotNumberSnapshot.map { "LOT \($0)" },
            store.displayName(for: movement.userId),
            movement.createdAt.formatted(date: .abbreviated, time: .shortened)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(itemName).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(movement.quantityDelta > 0 ? "+\(movement.quantityDelta)" : "\(movement.quantityDelta)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(movement.type.color)
                Text(movement.type.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private enum HistoryDateRange: String, CaseIterable, Identifiable {
    case all = "All time", week = "Last 7 days", month = "Last 30 days"
    var id: String { rawValue }
    var startDate: Date? {
        switch self {
        case .all: nil
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
        case .month: Calendar.current.date(byAdding: .day, value: -30, to: .now)
        }
    }
}
