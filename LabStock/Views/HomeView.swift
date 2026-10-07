import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30

    private var summary: DashboardSummary { store.dashboard(warningDays: warningDays) }
    private var attention: [ItemSnapshot] {
        store.snapshots.filter { snapshot in
            snapshot.totalQuantity <= snapshot.item.lowStockThreshold || snapshot.batches.contains {
                let status = InventoryRules.expiryStatus(for: $0.expiryDate, warningDays: warningDays)
                return status == .expired || status == .expiringSoon
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryCard(title: "Total Items", value: summary.totalItems, color: .blue, icon: "shippingbox")
                SummaryCard(title: "Low Stock", value: summary.lowStock, color: .orange, icon: "exclamationmark.triangle")
                SummaryCard(title: "Expiring Soon", value: summary.expiringSoon, color: .yellow, icon: "calendar.badge.clock")
                SummaryCard(title: "Expired", value: summary.expired, color: .red, icon: "calendar.badge.exclamationmark")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Needs Attention").font(.headline)
                if attention.isEmpty { EmptyStateView(title: "All Clear", message: "No inventory items need attention.", icon: "checkmark.circle") }
                else { ForEach(attention) { ItemRow(snapshot: $0, warningDays: warningDays) } }
                Text("Recent Movements").font(.headline).padding(.top)
                if store.movements.isEmpty { Text("No stock activity yet.").foregroundStyle(.secondary) }
                else { ForEach(store.movements.prefix(5)) { MovementRow(movement: $0) } }
            }.padding(.top, 20)
        }
        .padding().navigationTitle("LabStock").refreshable { await store.refresh() }
    }
}

private struct SummaryCard: View {
    let title: String; let value: Int; let color: Color; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title2)
            Text("\(value)").font(.title.bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
