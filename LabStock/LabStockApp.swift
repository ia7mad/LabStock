import SwiftUI

@main
struct LabStockApp: App {
    @StateObject private var store = InventoryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active, store.userID != nil { Task { await store.refresh() } }
                }
        }
    }
}

