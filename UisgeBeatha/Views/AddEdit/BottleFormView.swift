import OSLog
import SwiftData
import SwiftUI

/// Manual entry and edit form (PRD F2). Pass nil to create a new bottle.
/// Edits are staged in local state and only applied on Save, so Cancel
/// never leaves half-edited data behind.
struct BottleFormView: View {
    let bottle: Bottle?
    /// Pre-filled values from a scan lookup (new bottles only).
    var prefill: LookupPrefill?
    /// True when the barcode came from a scan and must not be edited.
    var barcodeIsLocked = false
    /// One-line banner, e.g. the lookup-miss notice.
    var notice: String?
    /// True for the barcode-miss path and the manual-entry entry point:
    /// offers "Scan Barcode" and "Scan Label" buttons that reopen the
    /// *live scanner* in that mode. Previously this offered a single
    /// button that opened a still-photo camera, which both looked like an
    /// unrelated "take a picture" mode and left no way back to barcode
    /// scanning without abandoning the form.
    var offersLabelScan = false
    /// A photo already captured for this bottle (from an accepted live
    /// label read), saved on first save so the scan doesn't discard the
    /// one good photo of this exact bottle.
    var initialPhotoData: Data?
    /// Called after a successful save, so scan sheets can dismiss the chain.
    var onSaved: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.expressionStore) private var expressionStore
    @Environment(\.imageStore) private var imageStore
    @Environment(\.stockPhotoBackfill) private var stockPhotoBackfill
    private var dismiss = ContextualDismiss()

    /// Read-only: seeds cask type autocomplete from what's already in the
    /// collection.
    @Query private var existingBottles: [Bottle]

    /// All field state lives in the draft, which keeps validation and label
    /// merging out of the view and lets the form survive being rebuilt.
    @State private var draft: BottleDraft
    /// Which mode the in-form scanner sheet is showing, nil when closed.
    @State private var activeScanMode: ScanMode?
    @State private var isSaving = false

    @FocusState private var distilleryFieldFocused: Bool
    @FocusState private var caskTypeFieldFocused: Bool

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "BottleForm")

    init(
        bottle: Bottle?,
        prefill: LookupPrefill? = nil,
        barcodeIsLocked: Bool = false,
        notice: String? = nil,
        offersLabelScan: Bool = false,
        initialPhotoData: Data? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.bottle = bottle
        self.prefill = prefill
        self.barcodeIsLocked = barcodeIsLocked
        self.notice = notice
        self.offersLabelScan = offersLabelScan
        self.initialPhotoData = initialPhotoData
        self.onSaved = onSaved
        _draft = State(initialValue: BottleDraft(
            bottle: bottle, prefill: prefill, initialPhotoData: initialPhotoData
        ))
    }

    private var fields: Bindable<BottleDraft> { Bindable(draft) }

    private var distillerySuggestions: [Distillery] {
        distilleryFieldFocused ? draft.distillerySuggestions(in: distilleryStore) : []
    }

    private var caskTypeSuggestions: [String] {
        caskTypeFieldFocused ? draft.caskTypeSuggestions(from: existingBottles.map(\.caskType)) : []
    }

    var body: some View {
        NavigationStack {
            Form {
                if notice != nil || offersLabelScan {
                    Section {
                        if let notice {
                            Label(notice, systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        // Both modes, always — the whole point is that
                        // there's an obvious way back to barcode scanning
                        // after a miss, not just a label camera.
                        if offersLabelScan, LiveScannerView.isSupported {
                            Button {
                                activeScanMode = .barcode
                            } label: {
                                Label(Strings.Scan.scanBarcode, systemImage: "barcode.viewfinder")
                            }
                            Button {
                                activeScanMode = .label
                            } label: {
                                Label(Strings.Scan.scanLabel, systemImage: "text.viewfinder")
                            }
                        }
                        if let banner = draft.labelScanBanner {
                            Text(banner)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(Strings.Form.bottleSection) {
                    TextField(Strings.Form.name, text: fields.name, prompt: Text(Strings.Form.namePlaceholder))
                    TextField(
                        Strings.Form.distillery,
                        text: fields.distilleryName,
                        prompt: Text(Strings.Form.distilleryPlaceholder)
                    )
                    .focused($distilleryFieldFocused)
                    .autocorrectionDisabled()
                    ForEach(distillerySuggestions) { suggestion in
                        Button {
                            select(suggestion)
                        } label: {
                            HStack {
                                Text(suggestion.name)
                                Spacer()
                                RegionTagView(regionID: suggestion.region)
                            }
                            // Make the gap between name and tag tappable too.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    regionPicker
                }

                Section(Strings.Form.detailSection) {
                    LabeledContent(Strings.Form.abv) {
                        TextField(Strings.Form.abv, value: fields.abv, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                    }
                    Toggle(Strings.Form.noAgeStatement, isOn: fields.isNAS)
                    if !draft.isNAS {
                        LabeledContent(Strings.Form.age) {
                            TextField(Strings.Form.age, value: fields.age, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .labelsHidden()
                        }
                    }
                    TextField(
                        Strings.Form.caskType,
                        text: fields.caskType,
                        prompt: Text(Strings.Form.caskTypePlaceholder)
                    )
                    .focused($caskTypeFieldFocused)
                    ForEach(caskTypeSuggestions, id: \.self) { suggestion in
                        Button {
                            draft.caskType = suggestion
                            caskTypeFieldFocused = false
                        } label: {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Picker(Strings.Form.status, selection: fields.status) {
                        // A bottle starts with no status rather than being
                        // silently declared Sealed; this is also how an
                        // already-set status gets cleared again.
                        Text(Strings.Form.statusPlaceholder).tag(BottleStatus?.none)
                        ForEach(BottleStatus.allCases, id: \.self) { status in
                            Text(Strings.Status.label(for: status)).tag(BottleStatus?.some(status))
                        }
                    }
                    if barcodeIsLocked {
                        LabeledContent(Strings.Form.barcode, value: draft.barcode)
                    } else {
                        LabeledContent(Strings.Form.barcode) {
                            TextField(Strings.Form.barcode, text: fields.barcode)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .labelsHidden()
                        }
                    }
                }

                Section(Strings.Form.purchaseSection) {
                    LabeledContent(Strings.Form.price) {
                        TextField(Strings.Form.price, value: fields.price, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                    }
                    Toggle(Strings.Form.hasPurchaseDate, isOn: fields.hasPurchaseDate)
                    if draft.hasPurchaseDate {
                        DatePicker(
                            Strings.Form.purchaseDate,
                            selection: fields.purchaseDate,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle(bottle == nil ? Strings.Form.newTitle : Strings.Form.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Form.cancel, role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Form.save) { save() }
                        .disabled(!draft.canSave || isSaving)
                }
            }
        }
        .fullScreenCover(item: $activeScanMode) { mode in
            InFormScannerSheet(
                mode: mode,
                onBarcode: { scanned in
                    draft.barcode = scanned
                    activeScanMode = nil
                },
                onLabel: { lines, photoData in
                    activeScanMode = nil
                    if let photoData { draft.labelPhotoData = photoData }
                    draft.applyLabelScan(
                        lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
                    )
                }
            )
        }
    }

    private var regionPicker: some View {
        Picker(Strings.Form.region, selection: fields.region) {
            Text(Strings.Form.regionPlaceholder).tag("")
            ForEach(RegionCatalog.regions) { region in
                Text(region.displayName).tag(region.id)
            }
        }
    }

    private func select(_ suggestion: Distillery) {
        draft.select(suggestion)
        distilleryFieldFocused = false
    }

    private func save() {
        draft.resolveRegionIfNeeded(using: distilleryStore)
        guard draft.canSave, !isSaving else { return }
        isSaving = true
        Task {
            let target = bottle ?? Bottle()
            draft.apply(to: target)
            let isNewBottle = bottle == nil
            if isNewBottle {
                // Keep the lookup's stock photo so rows and the detail hero can
                // show it until the owner takes their own (PRD F4).
                target.stockPhotoURL = draft.prefillStockPhotoURL
                // The photo captured for label scanning is the best available
                // photo of this exact bottle: save it as the user photo rather
                // than going to the internet for a stand-in. Encoded off the
                // main actor.
                if let photoData = draft.labelPhotoData,
                   let filename = try? await imageStore.save(imageData: photoData) {
                    target.userPhotoFilename = filename
                }
                modelContext.insert(target)
            }
            do {
                try modelContext.save()
                dismiss()
                onSaved?()
                // Only worth searching when the bottle still has no photo at
                // all: a barcode-hit stock photo or a label-scan user photo
                // both mean there's nothing to backfill.
                if isNewBottle, target.stockPhotoURL == nil, target.userPhotoFilename == nil {
                    stockPhotoBackfill?.fetch(
                        for: target, modelContext: modelContext,
                        distilleryWikipediaTitle: distilleryStore.exactMatch(target.distilleryName)?.wikipediaTitle
                    )
                }
            } catch {
                Self.logger.error("Failed to save bottle: \(error)")
                isSaving = false
            }
        }
    }
}

#Preview {
    BottleFormView(bottle: nil)
        .modelContainer(for: Bottle.self, inMemory: true)
}
