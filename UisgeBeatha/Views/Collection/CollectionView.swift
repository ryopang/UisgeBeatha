import OSLog
import SwiftData
import SwiftUI

/// The collection tab: searchable, sortable bottle list, or the region map
/// (List | Map toggle).
///
/// Two layouts share one set of state:
/// - **Compact width** (iPhone, the Duo's outer display): a navigation
///   stack that pushes detail.
/// - **Regular width** (the Duo's inner display, iPad): a split view with
///   the list in the sidebar and the selected bottle, or the map, beside it.
///
/// Everything that must survive a fold or unfold (selection, search text,
/// the add form, the delete confirmation, editors opened from a detail)
/// lives *above* the size-class switch, so rebuilding the layout beneath it
/// never discards a half-filled form.
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    /// Scene storage, so selection comes back after a fold, an unfold or a
    /// relaunch. Holds the bottle's UUID string; empty means none.
    @SceneStorage("collection.selectedBottle") private var storedSelection = ""
    @SceneStorage("collection.regionFilter") private var regionFilterID = ""

    @State private var searchText = ""
    @State private var showingAddForm = false
    @State private var bottlePendingDelete: Bottle?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "Collection")

    private var sortKey: CollectionSortKey {
        CollectionSortKey(rawValue: sortKeyRawValue) ?? .name
    }

    private var viewMode: ViewMode {
        ViewMode(rawValue: viewModeRawValue) ?? .list
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { CollectionSelection.id(fromStored: storedSelection) },
            set: { storedSelection = CollectionSelection.stored($0) }
        )
    }

    private var selectedBottle: Bottle? {
        CollectionSelection.bottle(for: selection.wrappedValue, in: Array(bottles))
    }

    /// The list's rows: search and sort, plus the region filter in map mode.
    private func visibleBottles(filteringRegion: Bool) -> [Bottle] {
        CollectionSelection.visible(
            Array(bottles),
            query: searchText,
            regionID: filteringRegion ? regionFilterID : "",
            sortKey: sortKey
        )
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
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
                    delete(bottle)
                }
                bottlePendingDelete = nil
            }
            Button(Strings.Collection.cancel, role: .cancel) {
                bottlePendingDelete = nil
            }
        } message: {
            Text(Strings.Collection.deleteConfirmMessage)
        }
        .editorRouting()
        // A selection pointing at a bottle that's gone (deleted, or removed
        // by a sync merge) must clear rather than leave the detail pane
        // blank with a stale highlight.
        .onChange(of: bottles.count) {
            if !storedSelection.isEmpty, selectedBottle == nil {
                storedSelection = ""
            }
        }
    }

    // MARK: - Compact (stack)

    private var compactLayout: some View {
        NavigationStack {
            Group {
                switch viewMode {
                case .list:
                    if bottles.isEmpty {
                        emptyState
                    } else {
                        compactList
                    }
                case .map:
                    // No sort, search, or add in map mode: none apply to a
                    // region map, and dropping them gives the map the full
                    // screen below the nav bar.
                    RegionMapView(bottles: Array(bottles))
                }
            }
            .navigationTitle(Strings.Collection.title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    viewModePicker
                        // minWidth, not maxWidth: a segmented control sizes
                        // to fit its labels by default, so a *maximum* alone
                        // never actually stretched it.
                        .frame(minWidth: 280)
                }
                if viewMode == .list {
                    ToolbarItem(placement: .topBarLeading) {
                        sortMenu
                    }
                    ToolbarItem(placement: .primaryAction) {
                        addButton
                    }
                }
            }
        }
    }

    private var compactList: some View {
        List {
            ForEach(visibleBottles(filteringRegion: false)) { bottle in
                NavigationLink {
                    BottleDetailView(bottle: bottle)
                } label: {
                    BottleRowView(bottle: bottle)
                }
                .swipeActions(edge: .leading) { statusSwipe(for: bottle) }
                .swipeActions(edge: .trailing) { deleteSwipe(for: bottle) }
            }
        }
        .searchable(text: $searchText, prompt: Strings.Collection.searchPrompt)
    }

    // MARK: - Regular (split view)

    @ViewBuilder
    private var regularLayout: some View {
        if bottles.isEmpty {
            NavigationStack {
                emptyState
                    .navigationTitle(Strings.Collection.title)
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailColumn
            }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            if viewMode == .map {
                Section {
                    Picker(Strings.Collection.regionFilter, selection: $regionFilterID) {
                        Text(Strings.Collection.allRegions).tag("")
                        ForEach(RegionCatalog.regions) { region in
                            Text(region.displayName).tag(region.id)
                        }
                    }
                }
            }
            // Explicit UUID ids and tags: selection is stored as the
            // bottle's own `id`, not SwiftData's persistent identifier.
            ForEach(visibleBottles(filteringRegion: viewMode == .map), id: \.id) { bottle in
                BottleRowView(bottle: bottle)
                    .tag(bottle.id)
                    .swipeActions(edge: .leading) { statusSwipe(for: bottle) }
                    .swipeActions(edge: .trailing) { deleteSwipe(for: bottle) }
            }
        }
        .searchable(text: $searchText, prompt: Strings.Collection.searchPrompt)
        .navigationTitle(Strings.Collection.title)
        .safeAreaInset(edge: .top) {
            viewModePicker
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                sortMenu
            }
            ToolbarItem(placement: .primaryAction) {
                addButton
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch viewMode {
        case .list:
            if let bottle = selectedBottle {
                // Keyed on the bottle so a new selection gets fresh
                // view state (photo, pending dialogs) instead of inheriting
                // the previous bottle's.
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                selectPrompt
            }
        case .map:
            // Choosing a bottle pushes its detail inside this column, and
            // Back returns to the map.
            NavigationStack {
                RegionMapView(bottles: Array(bottles), filteredRegionID: $regionFilterID)
                    .navigationTitle(Strings.Map.mapMode)
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(item: selection) { id in
                        if let bottle = CollectionSelection.bottle(for: id, in: Array(bottles)) {
                            BottleDetailView(bottle: bottle)
                        }
                    }
            }
        }
    }

    private var selectPrompt: some View {
        ContentUnavailableView {
            Label(Strings.Collection.selectTitle, systemImage: "wineglass")
        } description: {
            Text(Strings.Collection.selectMessage)
        } actions: {
            Button(Strings.Collection.emptyAction) {
                tabRouter?.selection = .scan
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Shared pieces

    private var viewModePicker: some View {
        Picker(Strings.Map.viewToggle, selection: $viewModeRawValue) {
            ForEach(ViewMode.allCases, id: \.rawValue) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    private var addButton: some View {
        Button(Strings.Collection.addBottle, systemImage: "plus") {
            showingAddForm = true
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

    @ViewBuilder
    private func statusSwipe(for bottle: Bottle) -> some View {
        Button(
            Strings.Collection.statusSwipeLabel,
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            bottle.status = BottleStatus.next(after: bottle.status)
            persistChanges()
        }
        .tint(.indigo)
    }

    @ViewBuilder
    private func deleteSwipe(for bottle: Bottle) -> some View {
        Button(Strings.Collection.delete, systemImage: "trash", role: .destructive) {
            bottlePendingDelete = bottle
        }
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

    // MARK: - Actions

    private func delete(_ bottle: Bottle) {
        // Deleting the selected bottle clears the selection; the detail
        // pane must not keep showing (or crash on) a deleted model.
        if bottle.id == selection.wrappedValue {
            storedSelection = ""
        }
        if let filename = bottle.userPhotoFilename {
            try? imageStore.delete(filename: filename)
            ThumbnailCache.shared.removeImage(forKey: filename)
        }
        modelContext.delete(bottle)
        persistChanges()
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
}

#Preview {
    CollectionView()
        .modelContainer(for: Bottle.self, inMemory: true)
}
