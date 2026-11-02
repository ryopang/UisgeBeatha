import OSLog
import PhotosUI
import SwiftData
import SwiftUI

/// Bottle detail (PRD F5): hero photo, facts grid, distillery card,
/// rating, tasting notes.
struct BottleDetailView: View {
    @Bindable var bottle: Bottle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.imageStore) private var imageStore
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.stockPhotoBackfill) private var stockPhotoBackfill
    @Environment(\.editorRouter) private var editorRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 320

    @State private var showingDeleteConfirm = false
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var notePendingDelete: TastingNote?
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Decoded off the main actor (see `loadHeroPhoto`): a synchronous
    /// `UIImage(contentsOfFile:)` on a full-size (up to 2000px) stored
    /// photo during body evaluation was a measured push hitch.
    @State private var heroImage: UIImage?
    @State private var heroThumbnail: UIImage?

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "BottleDetail")

    private var sortedNotes: [TastingNote] {
        (bottle.notes ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            // Two columns when the pane is wide enough (the iPhone Duo's
            // inner display, an iPad), one column otherwise. `ViewThatFits`
            // measures the ideal widths below instead of comparing against
            // a hard-coded breakpoint, so a split-view pane, Split View
            // multitasking and the outer display all pick correctly.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        heroSection
                        photoStatus
                        factsGrid
                    }
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 420)
                    VStack(spacing: 24) {
                        ratingSection
                        DistilleryCardView(distilleryName: bottle.distilleryName)
                        notesSection
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity)
                }
                VStack(spacing: 24) {
                    heroSection
                    photoStatus
                    factsGrid
                    DistilleryCardView(distilleryName: bottle.distilleryName)
                    ratingSection
                    notesSection
                }
            }
            .padding()
        }
        .navigationTitle(bottle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu(Strings.Detail.more, systemImage: "ellipsis.circle") {
                    Button(Strings.Detail.edit, systemImage: "pencil") {
                        editorRouter?.present(.editBottle(bottle))
                    }
                    Button(Strings.Detail.delete, systemImage: "trash", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                Task {
                    if let data = await PhotoEncoder.jpegDataOffMain(from: image) {
                        applyPhoto(data)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
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
        ZStack {
            // Bottles are tall. `scaledToFill` in a wide pane crops them,
            // so the image fits inside a neutral backdrop instead.
            RoundedRectangle(cornerRadius: Theme.Radius.hero)
                .fill(.quaternary.opacity(0.4))
            heroContent
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero))
        // The one deliberate shadow in the app: the bottle photo is the
        // "product" here, so it's the one surface that gets to rest above
        // the page instead of sitting flush with it.
        .heroShadow()
        .accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            photoMenu
                .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            // A distillery photo is always genuinely that distillery, but
            // never a photo of this specific bottle: labelled honestly
            // rather than passed off as a product shot. Left outside the
            // image's accessibilityHidden scope above: unlike the
            // decorative photo itself, this caption is information a
            // VoiceOver user should get too.
            if bottle.userPhotoFilename == nil, bottle.stockPhotoURL != nil, bottle.isDistilleryPhoto {
                Text(Strings.Detail.distilleryPhotoCaption)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private var heroContent: some View {
        if let filename = bottle.userPhotoFilename {
            Group {
                if let heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFit()
                } else if let heroThumbnail {
                    // The thumbnail is tiny (ImageStore caps it at 300px)
                    // and decodes near-instantly, so it stands in while the
                    // full-size photo loads off-main.
                    Image(uiImage: heroThumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    heroPlaceholder
                }
            }
            .task(id: filename) {
                await loadHeroPhoto(filename: filename)
            }
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

    /// With no image of any kind, the hero shows the bottle's *name* as
    /// text rather than a single-initial monogram: at this size there's
    /// room for the actual name, and a lone letter told you nothing you
    /// couldn't already see in the title.
    private var heroPlaceholder: some View {
        Text(bottle.name.isEmpty ? Strings.Form.newTitle : bottle.name)
            .font(.title2.weight(Theme.Weight.emphasis))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .foregroundStyle(RegionCatalog.region(id: bottle.region)?.textColor ?? .secondary)
            .padding(24)
    }

    /// Decodes off the main actor: thumbnail first (small, near-instant),
    /// then the full-size photo, so the view never blocks on
    /// `UIImage(contentsOfFile:)` during body evaluation. Cleared at the
    /// start so a stale image from a previous filename (a retaken photo)
    /// never flashes before the new one is ready.
    private func loadHeroPhoto(filename: String) async {
        heroImage = nil
        heroThumbnail = nil
        let thumbnailURL = imageStore.thumbnailURL(for: filename)
        let imageURL = imageStore.imageURL(for: filename)
        heroThumbnail = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: thumbnailURL.path)
        }.value
        guard !Task.isCancelled else { return }
        heroImage = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: imageURL.path)
        }.value
    }

    private var isSearchingStockPhoto: Bool {
        stockPhotoBackfill?.isSearching(bottle) ?? false
    }

    private var stockPhotoLookupFailed: Bool {
        stockPhotoBackfill?.lookupFailed(bottle) ?? false
    }

    /// One menu for every photo action (it used to be a row of up to four
    /// buttons that overflowed at large type sizes and on narrow screens).
    private var photoMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(Strings.Detail.takePhoto, systemImage: "camera") {
                    showingCamera = true
                }
            }
            Button(Strings.Detail.choosePhoto, systemImage: "photo.on.rectangle") {
                showingPhotoPicker = true
            }
            Button(Strings.Detail.lookUpPhoto, systemImage: "magnifyingglass") {
                // A person choosing this again clearly wants a fresh
                // attempt, not the same cached hit or miss re-served.
                stockPhotoBackfill?.fetch(
                    for: bottle, modelContext: modelContext,
                    distilleryWikipediaTitle: distilleryStore.exactMatch(bottle.distilleryName)?.wikipediaTitle,
                    bypassCache: true
                )
            }
            .disabled(isSearchingStockPhoto)
            if bottle.userPhotoFilename != nil {
                Button(Strings.Detail.removePhoto, systemImage: "trash", role: .destructive) {
                    removePhoto()
                }
            }
        } label: {
            Group {
                if isSearchingStockPhoto {
                    ProgressView()
                } else {
                    Image(systemName: "camera.fill")
                }
            }
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(Strings.Detail.photoMenu)
    }

    /// Search progress and failure, under the hero. Also covers the
    /// automatic backfill kicked off right after a label-OCR or manual
    /// save, so it's never running silently with nothing on screen.
    @ViewBuilder
    private var photoStatus: some View {
        if isSearchingStockPhoto {
            Text(Strings.Scan.lookingUp)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if stockPhotoLookupFailed {
            Text(Strings.Detail.lookUpPhotoFailure)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Facts

    private var factsGrid: some View {
        // Single column at accessibility sizes: two columns of large type
        // truncate or wrap values like cask types into unreadable slivers.
        LazyVGrid(columns: factColumns, spacing: 16) {
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

    private var factColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
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

    /// Tappable status: cycles (unset →) sealed → open → finished → sealed.
    /// Never cycles back to unset — clearing is deliberate, via the edit
    /// form's picker.
    private var statusCell: some View {
        Button {
            bottle.status = BottleStatus.next(after: bottle.status)
            persistChanges()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.Detail.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(bottle.status.map(Strings.Status.label(for:)) ?? Strings.Detail.statusNotSet)
                    .font(.body)
                    .foregroundStyle(bottle.status == nil ? Color.secondary : Color.accentColor)
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
                    editorRouter?.present(.newNote(bottle))
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
                        onEdit: { editorRouter?.present(.editNote(bottle, note)) },
                        onDelete: { notePendingDelete = note }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func applyPhoto(_ data: Data) {
        Task {
            do {
                // Encode off the main actor, then swap: save the new files
                // before removing the old ones, so a failed save never
                // costs the person their existing photo.
                let newFilename = try await imageStore.save(imageData: data)
                if let oldFilename = bottle.userPhotoFilename {
                    try? imageStore.delete(filename: oldFilename)
                    ThumbnailCache.shared.removeImage(forKey: oldFilename)
                }
                bottle.userPhotoFilename = newFilename
                persistChanges()
            } catch {
                Self.logger.error("Failed to store photo: \(error)")
            }
        }
    }

    /// Removes the owner's own photo and its files. Any stock or
    /// distillery photo the lookup found earlier is left in place and
    /// takes over the hero again; only when there's no image of any kind
    /// does the hero fall back to the bottle's name as text.
    private func removePhoto() {
        guard let filename = bottle.userPhotoFilename else { return }
        try? imageStore.delete(filename: filename)
        ThumbnailCache.shared.removeImage(forKey: filename)
        bottle.userPhotoFilename = nil
        heroImage = nil
        heroThumbnail = nil
        persistChanges()
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
