import OSLog
import PhotosUI
import SwiftData
import SwiftUI

/// Bottle detail (PRD F5): hero photo, facts grid, distillery card
/// (arrives in Phase 6), rating, tasting notes.
struct BottleDetailView: View {
    @Bindable var bottle: Bottle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.imageStore) private var imageStore
    @Environment(\.stockPhotoBackfill) private var stockPhotoBackfill
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditForm = false
    @State private var showingDeleteConfirm = false
    @State private var showingCamera = false
    @State private var showingNewNote = false
    @State private var noteBeingEdited: TastingNote?
    @State private var notePendingDelete: TastingNote?
    @State private var selectedPhotoItem: PhotosPickerItem?

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "BottleDetail")

    private var sortedNotes: [TastingNote] {
        (bottle.notes ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                photoButtons
                factsGrid
                DistilleryCardView(distilleryName: bottle.distilleryName)
                ratingSection
                notesSection
            }
            .padding()
        }
        .navigationTitle(bottle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu(Strings.Detail.more, systemImage: "ellipsis.circle") {
                    Button(Strings.Detail.edit, systemImage: "pencil") {
                        showingEditForm = true
                    }
                    Button(Strings.Detail.delete, systemImage: "trash", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditForm) {
            BottleFormView(bottle: bottle)
        }
        .sheet(isPresented: $showingNewNote) {
            TastingNoteEditorView(bottle: bottle, note: nil)
        }
        .sheet(item: $noteBeingEdited) { note in
            TastingNoteEditorView(bottle: bottle, note: note)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) {
                    applyPhoto(data)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) {
            guard let item = selectedPhotoItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    applyPhoto(data)
                }
                selectedPhotoItem = nil
            }
        }
        .confirmationDialog(
            Strings.Collection.deleteConfirmTitle,
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(Strings.Collection.delete, role: .destructive) { deleteBottle() }
            Button(Strings.Collection.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Collection.deleteConfirmMessage)
        }
        .confirmationDialog(
            Strings.Detail.deleteNoteTitle,
            isPresented: Binding(
                get: { notePendingDelete != nil },
                set: { if !$0 { notePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Strings.Collection.delete, role: .destructive) {
                if let note = notePendingDelete {
                    modelContext.delete(note)
                    persistChanges()
                }
                notePendingDelete = nil
            }
            Button(Strings.Collection.cancel, role: .cancel) {
                notePendingDelete = nil
            }
        }
    }

    // MARK: - Hero photo

    private var heroSection: some View {
        Group {
            if let filename = bottle.userPhotoFilename,
               let image = UIImage(contentsOfFile: imageStore.imageURL(for: filename).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let urlString = bottle.stockPhotoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    heroPlaceholder
                }
            } else {
                heroPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero))
        // The one deliberate shadow in the app: the bottle photo is the
        // "product" here, so it's the one surface that gets to rest above
        // the page instead of sitting flush with it.
        .heroShadow()
        .accessibilityHidden(true)
    }

    private var heroPlaceholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.hero)
            .fill(.quaternary.opacity(0.5))
            .overlay {
                MonogramThumbnail(name: bottle.name, regionID: bottle.region, size: 120)
            }
    }

    private var isSearchingStockPhoto: Bool {
        stockPhotoBackfill?.isSearching(bottle) ?? false
    }

    private var stockPhotoLookupFailed: Bool {
        stockPhotoBackfill?.lookupFailed(bottle) ?? false
    }

    private var photoButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(Strings.Detail.takePhoto, systemImage: "camera") {
                        showingCamera = true
                    }
                    .buttonStyle(.bordered)
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(Strings.Detail.choosePhoto, systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                Button {
                    // A person pressing this again clearly wants a fresh
                    // attempt, not the same cached hit or miss re-served.
                    stockPhotoBackfill?.fetch(for: bottle, modelContext: modelContext, bypassCache: true)
                } label: {
                    if isSearchingStockPhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSearchingStockPhoto)
                .accessibilityLabel(Strings.Detail.lookUpPhoto)
            }
            if isSearchingStockPhoto {
                // Also covers the automatic backfill kicked off right after
                // a label-OCR / manual save, so it's never running silently
                // with nothing on screen to explain it.
                Text(Strings.Scan.lookingUp)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if stockPhotoLookupFailed {
                Text(Strings.Detail.lookUpPhotoFailure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Facts

    private var factsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            factCell(Strings.Detail.distillery, bottle.distilleryName)
            factCell(
                Strings.Detail.region,
                RegionCatalog.region(id: bottle.region)?.displayName ?? bottle.region
            )
            factCell(Strings.Detail.abv, bottle.abv.map { "\($0.formatted())%" } ?? "—")
            factCell(Strings.Detail.age, bottle.ageStatement.map(Strings.Detail.ageValue) ?? Strings.Detail.nas)
            factCell(Strings.Detail.caskType, bottle.caskType ?? "—")
            statusCell
            factCell(
                Strings.Detail.price,
                bottle.purchasePrice.map { $0.formatted(.currency(code: bottle.currencyCode)) } ?? "—"
            )
            factCell(
                Strings.Detail.purchased,
                bottle.purchaseDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—"
            )
            factCell(Strings.Detail.added, bottle.dateAdded.formatted(date: .abbreviated, time: .omitted))
        }
        .cardBackground()
    }

    private func factCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Tappable status: cycles sealed → open → finished.
    private var statusCell: some View {
        Button {
            bottle.status = bottle.status.next
            persistChanges()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.Detail.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Strings.Status.label(for: bottle.status))
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Strings.Detail.statusHint)
    }

    // MARK: - Rating

    private var ratingSection: some View {
        VStack(spacing: 8) {
            Text(Strings.Detail.ratingSection)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            RatingControl(rating: Binding(
                get: { bottle.rating },
                set: { newValue in
                    bottle.rating = newValue
                    persistChanges()
                }
            ))
        }
    }

    // MARK: - Tasting notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Strings.Detail.notesSection)
                    .font(.headline)
                Spacer()
                Button(Strings.Detail.newNote, systemImage: "square.and.pencil") {
                    showingNewNote = true
                }
            }
            if sortedNotes.isEmpty {
                Text(Strings.Detail.noNotes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sortedNotes) { note in
                    TastingNoteCardView(
                        note: note,
                        onEdit: { noteBeingEdited = note },
                        onDelete: { notePendingDelete = note }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func applyPhoto(_ data: Data) {
        do {
            // Replacing a photo removes the old files first (PRD F5).
            if let oldFilename = bottle.userPhotoFilename {
                try? imageStore.delete(filename: oldFilename)
            }
            bottle.userPhotoFilename = try imageStore.save(imageData: data)
            persistChanges()
        } catch {
            Self.logger.error("Failed to store photo: \(error)")
        }
    }

    private func deleteBottle() {
        if let filename = bottle.userPhotoFilename {
            try? imageStore.delete(filename: filename)
        }
        modelContext.delete(bottle)
        persistChanges()
        dismiss()
    }

    private func persistChanges() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save bottle change: \(error)")
        }
    }
}
