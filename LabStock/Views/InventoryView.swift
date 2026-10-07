import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    @State private var search = ""
    @State private var showingGroups = false

    private var results: [ItemSnapshot] {
        guard let query = search.nilIfBlank?.lowercased() else { return [] }
        return store.snapshots.filter {
            $0.item.name.lowercased().contains(query)
                || ($0.item.referenceNumber?.lowercased().contains(query) ?? false)
                || ($0.item.manufacturer?.lowercased().contains(query) ?? false)
                || $0.batches.contains { $0.lotNumber?.lowercased().contains(query) ?? false }
        }
    }

    var body: some View {
        List {
            if search.nilIfBlank != nil {
                Section("Search Results") {
                    if results.isEmpty { Text("No matching items").foregroundStyle(.secondary) }
                    ForEach(results) { snapshot in itemLink(snapshot) }
                }
            } else {
                Section("Groups") {
                    ForEach(store.groups) { group in
                        NavigationLink {
                            GroupDetailView(group: group)
                        } label: {
                            HStack {
                                Label(group.name, systemImage: "folder")
                                Spacer()
                                Text("\(store.items.filter { $0.groupId == group.id }.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !store.items.filter({ $0.groupId == nil }).isEmpty {
                    Section("Ungrouped") {
                        ForEach(store.snapshots.filter { $0.item.groupId == nil }) { snapshot in itemLink(snapshot) }
                    }
                }
            }
        }
        .navigationTitle("Inventory")
        .searchable(text: $search, prompt: "Name, REF, maker, or lot")
        .toolbar { Button { showingGroups = true } label: { Label("Manage", systemImage: "folder.badge.gearshape") } }
        .sheet(isPresented: $showingGroups) { NavigationStack { GroupManagerView() } }
        .refreshable { await store.refresh() }
    }

    @ViewBuilder private func itemLink(_ snapshot: ItemSnapshot) -> some View {
        NavigationLink { ItemDetailView(snapshot: snapshot) } label: { ItemRow(snapshot: snapshot, warningDays: warningDays) }
    }
}

struct GroupDetailView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    let group: InventoryGroup
    @State private var showingAdd = false

    private var snapshots: [ItemSnapshot] { store.snapshots.filter { $0.item.groupId == group.id } }

    var body: some View {
        List {
            if snapshots.isEmpty {
                EmptyStateView(title: "No Items", message: "Add an item or use Scan to capture a reagent label.", icon: "shippingbox")
            }
            ForEach(snapshots) { snapshot in
                NavigationLink { ItemDetailView(snapshot: snapshot) } label: { ItemRow(snapshot: snapshot, warningDays: warningDays) }
            }
        }
        .navigationTitle(group.name)
        .toolbar { Button { showingAdd = true } label: { Label("Add Item", systemImage: "plus") } }
        .sheet(isPresented: $showingAdd) { AddItemView(groupID: group.id) }
    }
}

struct ItemDetailView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    let snapshot: ItemSnapshot
    @State private var operation: ScanMode?

    private var current: ItemSnapshot {
        store.snapshots.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: "\(current.totalQuantity) \(current.item.unitName)\(current.totalQuantity == 1 ? "" : "s")")
                if let ref = current.item.referenceNumber { LabeledContent("REF", value: ref) }
                if let maker = current.item.manufacturer { LabeledContent("Manufacturer", value: maker) }
                LabeledContent("Low stock at", value: "\(current.item.lowStockThreshold)")
            }
            Section("Batches") {
                if current.batches.isEmpty { Text("No batches yet.").foregroundStyle(.secondary) }
                ForEach(current.batches) { batch in BatchRow(batch: batch, warningDays: warningDays) }
            }
            Section("Recent History") {
                let history = store.movements.filter { $0.itemId == current.id }.prefix(20)
                if history.isEmpty { Text("No movements yet.").foregroundStyle(.secondary) }
                ForEach(history) { MovementRow(movement: $0) }
            }
        }
        .navigationTitle(current.item.name)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { operation = .add } label: { Label("Add Stock", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                Button { operation = .withdraw } label: { Label("Withdraw", systemImage: "minus.circle.fill").frame(maxWidth: .infinity) }
            }.buttonStyle(.borderedProminent).padding().background(.bar)
        }
        .sheet(item: $operation) { mode in StockOperationView(snapshot: current, mode: mode) }
    }
}

struct ItemRow: View {
    let snapshot: ItemSnapshot
    let warningDays: Int
    private var status: ExpiryStatus { InventoryRules.expiryStatus(for: snapshot.nearestExpiry, warningDays: warningDays) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.item.name).font(.headline)
                HStack {
                    Text("Qty \(snapshot.totalQuantity)")
                    if let date = snapshot.nearestExpiry { Text("• \(date, format: .dateTime.year().month().day())") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if snapshot.totalQuantity <= snapshot.item.lowStockThreshold { StatusDot(color: .orange, label: "Low") }
            if status == .expired { StatusDot(color: .red, label: "Expired") }
            else if status == .expiringSoon { StatusDot(color: .yellow, label: "Soon") }
        }
    }
}

private struct StatusDot: View {
    let color: Color; let label: String
    var body: some View { Circle().fill(color).frame(width: 10, height: 10).accessibilityLabel(label) }
}

private struct BatchRow: View {
    let batch: Batch; let warningDays: Int
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(batch.lotNumber.map { "LOT \($0)" } ?? "No lot")
                Text(batch.expiryDate.map { "Expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No expiry")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); Text("\(batch.currentQuantity)").font(.title3.monospacedDigit())
        }
    }
}

struct MovementRow: View {
    @EnvironmentObject private var store: InventoryStore
    let movement: StockMovement
    private var itemName: String { store.items.first(where: { $0.id == movement.itemId })?.name ?? "Unknown item" }
    private var lot: String? { movement.lotNumberSnapshot ?? movement.batchId.flatMap { id in store.batches.first(where: { $0.id == id })?.lotNumber } }
    private var userName: String { store.displayName(for: movement.userId) }
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(itemName).font(.subheadline.weight(.medium))
                Text([movement.type.label, lot.map { "LOT \($0)" }, userName, movement.createdAt.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(movement.quantityDelta > 0 ? "+\(movement.quantityDelta)" : "\(movement.quantityDelta)")
                .font(.headline.monospacedDigit()).foregroundStyle(movement.quantityDelta >= 0 ? .green : .red)
        }
    }
}

struct GroupManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    @State private var newName = ""
    @State private var editing: InventoryGroup?
    @State private var editName = ""

    var body: some View {
        List {
            Section("New Group") {
                HStack {
                    TextField("Group name", text: $newName)
                    Button("Add") {
                        Task {
                            do { try await store.createGroup(name: newName); newName = "" }
                            catch { store.errorMessage = error.localizedDescription }
                        }
                    }
                        .disabled(newName.nilIfBlank == nil)
                }
            }
            Section("Groups") {
                ForEach(store.groups) { group in
                    Text(group.name).swipeActions {
                        Button(role: .destructive) {
                            Task {
                                do { try await store.deleteGroup(group) }
                                catch { store.errorMessage = error.localizedDescription }
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = group; editName = group.name } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Manage Groups")
        .toolbar { Button("Done") { dismiss() } }
        .alert("Rename Group", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Name", text: $editName)
            Button("Save") {
                if let group = editing {
                    Task {
                        do { try await store.renameGroup(group, name: editName) }
                        catch { store.errorMessage = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let groupID: UUID?
    @State private var name = ""
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form { TextField("Item name", text: $name) }
                .navigationTitle("Add Item")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saving = true
                            Task {
                                do { try await store.createItem(name: name, groupID: groupID); dismiss() }
                                catch { store.errorMessage = error.localizedDescription }
                                saving = false
                            }
                        }.disabled(name.nilIfBlank == nil || saving)
                    }
                }
        }
    }
}

struct EmptyStateView: View {
    let title: String; let message: String; let icon: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}
