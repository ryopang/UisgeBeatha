import SwiftData
import SwiftUI

/// App root: Collection and Settings tabs.
/// The prominent Scan action joins the tab bar in Phase 4.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab(Strings.Tabs.collection, systemImage: "square.grid.2x2") {
                CollectionView()
            }
            Tab(Strings.Tabs.settings, systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Bottle.self, inMemory: true)
}
