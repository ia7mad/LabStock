import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    @State private var search = ""
    @State private var selectedGroupID: UUID?
    @State private var showingGroups = false
    @State private var exportReport: ExportReport?
    @State private var showingAddItem = false
    @State private var actionSnapshot: ItemSnapshot?
    @State private var actionMode: ScanMode = .add

    private var snapshots: [ItemSnapshot] {
        let query = search.nilIfBlank?.lowercased()
        return store.snapshots.filter { snapshot in
            guard selectedGroupID == nil || snapshot.item.groupId == selectedGroupID else { return false }
            guard let query else { return true }
            return snapshot.item.name.lowercased().contains(query)
                || (snapshot.item.referenceNumber?.lowercased().contains(query) ?? false)
                || (snapshot.item.manufacturer?.lowercased().contains(query) ?? false)
                || snapshot.batches.contains { $0.lotNumber?.lowercased().contains(query) ?? false }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            groupChips
            List {
                if snapshots.isEmpty {
                    EmptyStateView(
                        title: "No inventory yet",
                        message: "Scan your first reagent or add one manually.",
                        icon: "shippingbox",
                        primaryTitle: "Add Manually",
                        primaryAction: { showingAddItem = true },
                        secondaryTitle: "Manage Groups",
                        secondaryAction: { showingGroups = true }
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(snapshots) { snapshot in
                    NavigationLink { ItemDetailView(snapshot: snapshot) } label: {
                        ItemCard(snapshot: snapshot, warningDays: warningDays)
                    }
                    .swipeActions(edge: .trailing) {
                        Button { actionSnapshot = snapshot; actionMode = .add } label: { Label("Add", systemImage: "plus") }
                            .tint(LabTheme.teal)
                        Button { actionSnapshot = snapshot; actionMode = .withdraw } label: { Label("Withdraw", systemImage: "minus") }
                            .tint(.red)
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $search, prompt: "Name, REF, maker, or lot")
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingAddItem = true } label: { Label("Add Item", systemImage: "plus") }
                    Button { showingGroups = true } label: { Label("Manage Groups", systemImage: "folder.badge.gearshape") }
                    Menu {
                        Button("Inventory PDF") { exportReport = .inventoryPDF }
                        Button("Inventory CSV") { exportReport = .inventoryCSV }
                        Button("History CSV") { exportReport = .historyCSV }
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingGroups) { NavigationStack { GroupManagerView() } }
        .sheet(item: $exportReport) { report in ExportView(initialReport: report) }
        .sheet(isPresented: $showingAddItem) { AddItemView(groupID: selectedGroupID) }
        .sheet(item: $actionSnapshot) { snapshot in
            StockOperationView(snapshot: snapshot, mode: actionMode)
        }
        .refreshable { await store.refresh() }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedGroupID == nil) { selectedGroupID = nil }
                ForEach(store.groups) { group in
                    FilterChip(title: group.name, isSelected: selectedGroupID == group.id) { selectedGroupID = group.id }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}

struct ItemCard: View {
    let snapshot: ItemSnapshot
    let warningDays: Int

    private var status: ExportStatus { snapshot.status(warningDays: warningDays) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LabTheme.cyan.opacity(0.15))
                Image(systemName: "testtube.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LabTheme.cyan)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.item.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let maker = snapshot.item.manufacturer { Text(maker).lineLimit(1) }
                    if let ref = snapshot.item.referenceNumber { Text("REF \(ref)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("Qty \(snapshot.totalQuantity)")
                        .font(.subheadline.weight(.semibold))
                    if let expiry = snapshot.nearestExpiry {
                        Text("• \(expiry.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            StatusBadge(text: status.rawValue, color: status.color)
        }
        .padding(.vertical, 4)
    }
}

struct AddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InventoryStore
    let groupID: UUID?
    @State private var name = ""
    @State private var manufacturer = ""
    @State private var reference = ""
    @State private var unitName = "unit"
    @State private var lowStockThreshold = 1
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Reagent") {
                    TextField("Item name", text: $name)
                    TextField("Manufacturer", text: $manufacturer)
                    TextField("REF / Catalog No.", text: $reference).textInputAutocapitalization(.characters)
                }
                Section("Stock rules") {
                    TextField("Unit", text: $unitName)
                    Stepper("Low stock at \(lowStockThreshold)", value: $lowStockThreshold, in: 0...999)
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await store.createItem(
                                    name: name,
                                    groupID: groupID,
                                    manufacturer: manufacturer,
                                    referenceNumber: reference,
                                    unitName: unitName,
                                    lowStockThreshold: lowStockThreshold
                                )
                                dismiss()
                            } catch { store.errorMessage = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(name.nilIfBlank == nil || saving)
                }
            }
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
                if store.groups.isEmpty {
                    Text("No groups yet.").foregroundStyle(.secondary)
                }
                ForEach(store.groups) { group in
                    Text(group.name).swipeActions {
                        Button(role: .destructive) {
                            Task {
                                do { try await store.deleteGroup(group) }
                                catch { store.errorMessage = error.localizedDescription }
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = group; editName = group.name } label: { Label("Rename", systemImage: "pencil") }.tint(LabTheme.cyan)
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
