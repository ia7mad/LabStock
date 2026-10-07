import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    @State private var showingAddItem = false
    @State private var showingExport = false

    private var summary: DashboardSummary { store.dashboard(warningDays: warningDays) }
    private var attention: [ItemSnapshot] {
        store.snapshots.filter { $0.status(warningDays: warningDays) != .normal }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HeroCard(
                    caption: "TOTAL STOCK",
                    value: "\(store.totalQuantity)",
                    title: "\(summary.totalItems) items • \(store.batches.count) batches"
                )
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricCard(value: "\(summary.totalItems)", title: "Items", symbol: "shippingbox.fill", tint: LabTheme.deepBlue)
                    MetricCard(value: "\(summary.lowStock)", title: "Low Stock", symbol: "exclamationmark.triangle.fill", tint: LabTheme.amber)
                    MetricCard(value: "\(summary.expiringSoon)", title: "Expiring", symbol: "calendar.badge.clock", tint: .orange)
                    MetricCard(value: "\(summary.expired)", title: "Expired", symbol: "calendar.badge.exclamationmark", tint: .red)
                }
                attentionSection
                activitySection
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("LabStock")
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingAddItem = true } label: { Label("Add Item", systemImage: "plus") }
                    Button { showingExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showingAddItem) { AddItemView(groupID: nil) }
        .sheet(isPresented: $showingExport) { ExportView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting).font(.subheadline).foregroundStyle(.secondary)
            Text(attention.isEmpty ? "Inventory is healthy" : "\(attention.count) item\(attention.count == 1 ? "" : "s") need attention")
                .font(.title3.bold())
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs Attention").font(.headline)
            if attention.isEmpty {
                EmptyStateView(title: "All clear", message: "No low stock or expiry warnings right now.", icon: "checkmark.seal.fill")
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(attention.prefix(6)) { snapshot in
                        NavigationLink { ItemDetailView(snapshot: snapshot) } label: {
                            ItemCard(snapshot: snapshot, warningDays: warningDays)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity").font(.headline)
            if store.movements.isEmpty {
                EmptyStateView(title: "No activity yet", message: "Add or withdraw stock to see history here.", icon: "clock")
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(store.movements.prefix(5)) { movement in
                        MovementRow(movement: movement)
                        if movement.id != store.movements.prefix(5).last?.id { Divider() }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
            }
        }
    }
}
