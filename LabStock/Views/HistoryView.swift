import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var groupID: UUID?
    @State private var itemID: UUID?
    @State private var movementType: MovementType?
    @State private var userID: UUID?
    @State private var dateRange = HistoryDateRange.all
    @State private var showingFilters = false

    private var filtered: [StockMovement] {
        store.movements.filter { movement in
            let item = store.items.first(where: { $0.id == movement.itemId })
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
            if filtered.isEmpty { EmptyStateView(title: "No Movements", message: "Stock activity will appear here.", icon: "clock") }
            ForEach(filtered) { MovementRow(movement: $0) }
        }
        .navigationTitle("History")
        .toolbar { Button { showingFilters = true } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") } }
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
                    ToolbarItem(placement: .cancellationAction) { Button("Reset") { groupID = nil; itemID = nil; movementType = nil; userID = nil; dateRange = .all } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingFilters = false } }
                }
            }
        }
        .refreshable { await store.refresh() }
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
