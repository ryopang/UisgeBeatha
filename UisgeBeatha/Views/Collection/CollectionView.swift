import OSLog
import SwiftData
import SwiftUI

/// The collection tab: searchable, sortable bottle list.
/// (The List | Map toggle arrives in Phase 5.)
struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bottles: [Bottle]

    @Environment(\.imageStore) private var imageStore

    @AppStorage("collectionSortKey") private var sortKeyRawValue = CollectionSortKey.name.rawValue
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

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    emptyState
                } else {
                    bottleList
                }
            }
            .navigationTitle(Strings.Collection.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(Strings.Collection.addBottle, systemImage: "plus") {
                        showingAddForm = true
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
                        bottle.status = bottle.status.next
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
            // Becomes the scan action once the scanner lands in Phase 4.
            Button(Strings.Collection.emptyAction) {
                showingAddForm = true
            }
            .buttonStyle(.borderedProminent)
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
