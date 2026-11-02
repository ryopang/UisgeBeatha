import SwiftData
import SwiftUI

enum RootTab: Hashable {
    case collection
    case scan
    case settings
}

/// Lets deep views (e.g. the empty state's scan button) switch tabs.
@MainActor @Observable
final class TabRouter {
    var selection: RootTab = .collection
}

extension EnvironmentValues {
    @Entry var tabRouter: TabRouter?
}

/// App root: Collection, Scan, and Settings tabs.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TabRouter()
    /// Finishes the v1 photo migration, fills derived fields and merges
    /// duplicates that sync leaves behind.
    @State private var maintenance = StoreMaintenance()

    var body: some View {
        TabView(selection: Bindable(router).selection) {
            Tab(Strings.Tabs.collection, systemImage: "square.grid.2x2", value: RootTab.collection) {
                CollectionView()
            }
            Tab(Strings.Tabs.scan, systemImage: "barcode.viewfinder", value: RootTab.scan) {
                ScanView()
            }
            Tab(Strings.Tabs.settings, systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
            }
        }
        .environment(\.tabRouter, router)
        .task {
            maintenance.observeRemoteChanges(in: modelContext)
            await maintenance.runAll(in: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                maintenance.scheduleDedupe(in: modelContext)
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Bottle.self, inMemory: true)
}
