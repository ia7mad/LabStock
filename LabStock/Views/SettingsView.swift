import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: InventoryStore
    @AppStorage("expiryWarningDays") private var warningDays = 30
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var showingGroups = false

    var body: some View {
        Form {
            Section("Account") {
                if let id = store.userID { LabeledContent("User", value: String(id.uuidString.prefix(8))) }
                Button("Log Out", role: .destructive) { Task { await store.signOut() } }
            }
            Section("Inventory") {
                Button("Manage Groups") { showingGroups = true }
                Stepper("Expiry warning: \(warningDays) days", value: $warningDays, in: 1...365)
            }
            Section("Notifications") {
                Toggle("Inventory alerts", isOn: $notificationsEnabled)
                Text("Expired, expiring-soon, and low-stock alerts are grouped and scheduled daily. These statuses remain visible on Home when alerts are off.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingGroups) { NavigationStack { GroupManagerView() } }
        .onChange(of: notificationsEnabled) { enabled in
            Task { @MainActor in
                if enabled {
                    let granted = await NotificationService.shared.requestPermission()
                    if !granted { notificationsEnabled = false; return }
                }
                do { try await store.updatePreferences(warningDays: warningDays, notificationsEnabled: enabled) }
                catch { store.errorMessage = error.localizedDescription }
                await NotificationService.shared.reschedule(snapshots: store.snapshots)
            }
        }
        .onChange(of: warningDays) { _ in
            Task { @MainActor in
                do { try await store.updatePreferences(warningDays: warningDays, notificationsEnabled: notificationsEnabled) }
                catch { store.errorMessage = error.localizedDescription }
                await NotificationService.shared.reschedule(snapshots: store.snapshots)
            }
        }
    }
}
