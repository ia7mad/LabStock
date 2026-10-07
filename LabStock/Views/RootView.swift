import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: InventoryStore

    var body: some View {
        Group {
            if !AppConfig.isConfigured {
                ConfigurationRequiredView()
            } else if store.userID == nil {
                AuthView()
            } else if store.isLoading && store.groups.isEmpty && store.items.isEmpty {
                ProgressView("Loading inventory…")
            } else if store.groups.isEmpty {
                FirstRunView()
            } else {
                MainTabView()
            }
        }
        .tint(LabTheme.cyan)
        .alert("LabStock", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "") }
    }
}

private struct ConfigurationRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Supabase setup required").font(.title2.bold())
            Text("Add your project URL and publishable key to Config.xcconfig, then run the included SQL migration.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }.padding(28)
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { InventoryView() }
                .tabItem { Label("Inventory", systemImage: "shippingbox.fill") }
            NavigationStack { ScanView() }
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

private struct FirstRunView: View {
    @EnvironmentObject private var store: InventoryStore
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 56)).foregroundStyle(.tint)
                Text("Create your first group").font(.title2.bold())
                Text("Groups organize inventory by analyzer, department, or any label your laboratory uses.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextField("Example: AU5800 or General", text: $name)
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.words)
                Button {
                    saving = true
                    Task {
                        do { try await store.createGroup(name: name) }
                        catch { store.errorMessage = error.localizedDescription }
                        saving = false
                    }
                } label: {
                    if saving { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Create Group").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(name.nilIfBlank == nil || saving)
            }
            .padding(28).navigationTitle("Welcome to LabStock")
        }
    }
}
