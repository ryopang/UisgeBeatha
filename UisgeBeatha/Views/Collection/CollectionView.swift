import OSLog
import SwiftData
import SwiftUI

/// The collection tab: searchable, sortable bottle list.
/// (The List | Map toggle arrives in Phase 5.)
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bottles: [Bottle]

    @Environment(\.imageStore) private var imageStore
    @Environment(\.tabRouter) private var tabRouter

    enum ViewMode: String, CaseIterable {
        case list
        case map

        var label: String {
            switch self {
            case .list: Strings.Map.listMode
            case .map: Strings.Map.mapMode
            }
        }
    }

    @AppStorage("collectionSortKey") private var sortKeyRawValue = CollectionSortKey.name.rawValue
    @AppStorage("collectionViewMode") private var viewModeRawValue = ViewMode.list.rawValue
    @State private var searchText = ""
    @State private var showingAddForm = false
    @State private var bottlePendingDelete: Bottle?

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "Collection")

    private var sortKey: CollectionSortKey {
        CollectionSortKey(rawValue: sortKeyRawValue) ?? .name
    }

    private var visibleBottles: [Bottle] {
        let filtered = searchText.isEmpty
            ? bottles
            : bottles.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.distilleryName.localizedCaseInsensitiveContains(searchText)
            }
        return sortKey.sorted(filtered)
    }

    private var viewMode: ViewMode {
        ViewMode(rawValue: viewModeRawValue) ?? .list
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewMode {
                case .list:
                    if bottles.isEmpty {
                        emptyState
                    } else {
                        bottleList
                    }
                case .map:
                    // No sort, search, or add in map mode — none apply to a
                    // region map, and dropping them (plus the dedicated
                    // toggle row list mode still needs) gives the map the
                    // full screen below the nav bar.
                    RegionMapView(bottles: Array(bottles))
                }
            }
            .navigationTitle(Strings.Collection.title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(Strings.Map.viewToggle, selection: $viewModeRawValue) {
                        ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    // minWidth, not maxWidth: a segmented control sizes to
                    // fit its labels by default, so a *maximum* alone never
                    // actually stretched it — only a minimum forces the
                    // extra width.
                    .frame(minWidth: 280)
                }
                if viewMode == .list {
                    ToolbarItem(placement: .topBarLeading) {
                        sortMenu
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(Strings.Collection.addBottle, systemImage: "plus") {
                            showingAddForm = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddForm) {
                BottleFormView(bottle: nil)
            }
            .confirmationDialog(
                Strings.Collection.deleteConfirmTitle,
                isPresented: Binding(
                    get: { bottlePendingDelete != nil },
                    set: { if !$0 { bottlePendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(Strings.Collection.delete, role: .destructive) {
                    if let bottle = bottlePendingDelete {
                        if let filename = bottle.userPhotoFilename {
                            try? imageStore.delete(filename: filename)
                        }
                        modelContext.delete(bottle)
                        persistChanges()
                    }
                    bottlePendingDelete = nil
                }
                Button(Strings.Collection.cancel, role: .cancel) {
                    bottlePendingDelete = nil
                }
            } message: {
                Text(Strings.Collection.deleteConfirmMessage)
            }
        }
    }

    private var bottleList: some View {
        List {
            ForEach(visibleBottles) { bottle in
                NavigationLink {
                    BottleDetailView(bottle: bottle)
                } label: {
                    BottleRowView(bottle: bottle)
                }
                .swipeActions(edge: .leading) {
                    Button(
                        Strings.Collection.statusSwipeLabel,
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        bottle.status = BottleStatus.next(after: bottle.status)
                        persistChanges()
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .trailing) {
                    Button(Strings.Collection.delete, systemImage: "trash", role: .destructive) {
                        bottlePendingDelete = bottle
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Strings.Collection.searchPrompt)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.Collection.emptyTitle, systemImage: "wineglass")
        } description: {
            Text(Strings.Collection.emptyMessage)
        } actions: {
            Button(Strings.Collection.emptyAction) {
                tabRouter?.selection = .scan
            }
            .buttonStyle(.borderedProminent)
            Button(Strings.Collection.emptyManualAction) {
                showingAddForm = true
            }
            .buttonStyle(.bordered)
        }
    }

    /// Autosave alone loses changes if the app is force-killed right after a
    /// swipe action, so destructive and status mutations save explicitly.
    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save collection change: \(error)")
        }
    }

    private var sortMenu: some View {
        Menu(Strings.Collection.sort, systemImage: "arrow.up.arrow.down") {
            Picker(Strings.Collection.sort, selection: $sortKeyRawValue) {
                ForEach(CollectionSortKey.allCases, id: \.rawValue) { key in
                    Text(key.label).tag(key.rawValue)
                }
            }
        }
    }
}

#Preview {
    CollectionView()
        .modelContainer(for: Bottle.self, inMemory: true)
}
