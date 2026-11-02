import OSLog
import SwiftData
import SwiftUI

/// What a scan lookup pre-fills into the form (PRD F1 hit and miss paths).
struct LookupPrefill: Sendable {
    var name = ""
    var distilleryName = ""
    var region = ""
    var abv: Double?
    var age: Int?
    var barcode: String?
    var stockPhotoURL: String?
}

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
    @Environment(\.labelOCR) private var labelOCR
    @Environment(\.imageStore) private var imageStore
    @Environment(\.stockPhotoBackfill) private var stockPhotoBackfill
    @Environment(\.dismiss) private var dismiss

    /// Read-only: seeds cask type autocomplete from what's already in the
    /// collection (PRD out-of-scope note aside, this costs nothing beyond a
    /// query and makes cask type actually consistent enough to filter on
    /// later, rather than N free-text spellings of the same thing).
    @Query private var existingBottles: [Bottle]

    @State private var name: String
    @State private var distilleryName: String
    @State private var region: String
    @State private var abv: Double?
    @State private var isNAS: Bool
    @State private var age: Int?
    @State private var caskType: String
    @State private var price: Decimal?
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    /// nil means "not filled in" — a new bottle starts with no status
    /// rather than being silently declared Sealed.
    @State private var status: BottleStatus?
    @State private var barcode: String
    /// Which mode the in-form scanner sheet is showing, nil when closed.
    @State private var activeScanMode: ScanMode?
    @State private var isScanningLabel = false
    @State private var labelScanBanner: String?
    /// The photo for this bottle, kept regardless of whether OCR could read
    /// anything off it — it's the best available photo of this exact
    /// bottle. Previously discarded the moment OCR finished, after which
    /// the app would go to the *internet* looking for a photo of the
    /// bottle already in hand.
    @State private var labelPhotoData: Data?

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
        _name = State(initialValue: bottle?.name ?? prefill?.name ?? "")
        _distilleryName = State(initialValue: bottle?.distilleryName ?? prefill?.distilleryName ?? "")
        _region = State(initialValue: bottle?.region ?? prefill?.region ?? "")
        _abv = State(initialValue: bottle?.abv ?? prefill?.abv)
        let resolvedAge = bottle?.ageStatement ?? prefill?.age
        _isNAS = State(initialValue: bottle.map { $0.ageStatement == nil } ?? false)
        _age = State(initialValue: resolvedAge)
        _caskType = State(initialValue: bottle?.caskType ?? "")
        _price = State(initialValue: bottle?.purchasePrice)
        _hasPurchaseDate = State(initialValue: bottle?.purchaseDate != nil)
        _purchaseDate = State(initialValue: bottle?.purchaseDate ?? .now)
        _status = State(initialValue: bottle?.status)
        _barcode = State(initialValue: bottle?.barcode ?? prefill?.barcode ?? "")
        _labelPhotoData = State(initialValue: initialPhotoData)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !distilleryName.trimmingCharacters(in: .whitespaces).isEmpty
            && RegionCatalog.region(id: region) != nil
            && valuesAreInRange
    }

    /// Guards against typos like "430" for 43% or a negative price, which
    /// the number fields otherwise accept and would then show in the
    /// detail view and exports.
    private var valuesAreInRange: Bool {
        (abv.map { (0...100).contains($0) } ?? true)
            && (isNAS || (age.map { (0...100).contains($0) } ?? true))
            && (price.map { $0 >= 0 } ?? true)
    }

    private var distillerySuggestions: [Distillery] {
        guard distilleryFieldFocused else { return [] }
        let query = DistilleryStore.normalize(distilleryName)
        guard !query.isEmpty else { return [] }
        let matches = distilleryStore.distilleries.filter {
            DistilleryStore.normalize($0.name).contains(query)
        }
        // Hide the list once the field exactly names the only match.
        if matches.count == 1, DistilleryStore.normalize(matches[0].name) == query {
            return []
        }
        return Array(
            matches
                .sorted {
                    let lhsPrefix = DistilleryStore.normalize($0.name).hasPrefix(query)
                    let rhsPrefix = DistilleryStore.normalize($1.name).hasPrefix(query)
                    return lhsPrefix == rhsPrefix ? $0.name < $1.name : lhsPrefix
                }
                .prefix(6)
        )
    }

    /// Distinct cask types already in the collection, filtered to the
    /// current input — same shape as `distillerySuggestions`, just sourced
    /// from the user's own data instead of the seed catalog.
    private var caskTypeSuggestions: [String] {
        guard caskTypeFieldFocused else { return [] }
        let allTypes = Set(existingBottles.compactMap {
            $0.caskType?.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
        let query = caskType.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty
            ? allTypes
            : allTypes.filter { $0.localizedCaseInsensitiveContains(query) }
        // Hide the list once the field exactly names the only match.
        if matches.count == 1, matches.first?.localizedCaseInsensitiveCompare(query) == .orderedSame {
            return []
        }
        return Array(matches.sorted().prefix(6))
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
                            .disabled(isScanningLabel)
                            Button {
                                activeScanMode = .label
                            } label: {
                                if isScanningLabel {
                                    Label(Strings.Scan.lookingUp, systemImage: "text.viewfinder")
                                } else {
                                    Label(Strings.Scan.scanLabel, systemImage: "text.viewfinder")
                                }
                            }
                            .disabled(isScanningLabel)
                        }
                        if let labelScanBanner {
                            Text(labelScanBanner)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(Strings.Form.bottleSection) {
                    TextField(Strings.Form.name, text: $name, prompt: Text(Strings.Form.namePlaceholder))
                    TextField(
                        Strings.Form.distillery,
                        text: $distilleryName,
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
                        TextField(Strings.Form.abv, value: $abv, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                    }
                    Toggle(Strings.Form.noAgeStatement, isOn: $isNAS)
                    if !isNAS {
                        LabeledContent(Strings.Form.age) {
                            TextField(Strings.Form.age, value: $age, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .labelsHidden()
                        }
                    }
                    TextField(
                        Strings.Form.caskType,
                        text: $caskType,
                        prompt: Text(Strings.Form.caskTypePlaceholder)
                    )
                    .focused($caskTypeFieldFocused)
                    ForEach(caskTypeSuggestions, id: \.self) { suggestion in
                        Button {
                            caskType = suggestion
                            caskTypeFieldFocused = false
                        } label: {
                            Text(suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Picker(Strings.Form.status, selection: $status) {
                        // A bottle starts with no status rather than being
                        // silently declared Sealed; this is also how an
                        // already-set status gets cleared again.
                        Text(Strings.Form.statusPlaceholder).tag(BottleStatus?.none)
                        ForEach(BottleStatus.allCases, id: \.self) { status in
                            Text(Strings.Status.label(for: status)).tag(BottleStatus?.some(status))
                        }
                    }
                    if barcodeIsLocked {
                        LabeledContent(Strings.Form.barcode, value: barcode)
                    } else {
                        LabeledContent(Strings.Form.barcode) {
                            TextField(Strings.Form.barcode, text: $barcode)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .labelsHidden()
                        }
                    }
                }

                Section(Strings.Form.purchaseSection) {
                    LabeledContent(Strings.Form.price) {
                        TextField(Strings.Form.price, value: $price, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .labelsHidden()
                    }
                    Toggle(Strings.Form.hasPurchaseDate, isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker(
                            Strings.Form.purchaseDate,
                            selection: $purchaseDate,
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
                        .disabled(!canSave)
                }
            }
        }
        .fullScreenCover(item: $activeScanMode) { mode in
            InFormScannerSheet(
                mode: mode,
                onBarcode: { scanned in
                    barcode = scanned
                    activeScanMode = nil
                },
                onLabel: { lines, photoData in
                    activeScanMode = nil
                    if let photoData { labelPhotoData = photoData }
                    Task {
                        isScanningLabel = true
                        applyLabelScan(lines: lines)
                        isScanningLabel = false
                    }
                }
            )
        }
    }

    private var regionPicker: some View {
        Picker(Strings.Form.region, selection: $region) {
            Text(Strings.Form.regionPlaceholder).tag("")
            ForEach(RegionCatalog.regions) { region in
                Text(region.displayName).tag(region.id)
            }
        }
    }

    private func select(_ suggestion: Distillery) {
        distilleryName = suggestion.name
        region = suggestion.region
        distilleryFieldFocused = false
    }

    /// Applies whatever the live label scan read. Only fills fields that
    /// got a new value — never blanks something the person already typed
    /// just because this particular read didn't confirm it.
    ///
    /// Takes already-recognized lines rather than an image: the in-form
    /// scanner is the same live VisionKit session the Scan tab uses, so
    /// recognition has already happened by the time this is called.
    private func applyLabelScan(lines: [String]) {
        guard let result = LabelParser.parse(
            lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
        ) else {
            labelScanBanner = Strings.Form.labelScanFailure
            return
        }
        if !result.name.isEmpty { name = result.name }
        if !result.distilleryName.isEmpty { distilleryName = result.distilleryName }
        if !result.region.isEmpty { region = result.region }
        if let abv = result.abv { self.abv = abv }
        if result.isNAS { isNAS = true }
        if let age = result.age {
            self.age = age
            isNAS = false
        }
        labelScanBanner = result.distilleryProvenance == .guessed
            ? Strings.Form.labelScanUncertain
            : Strings.Form.labelScanSuccess
    }

    private func save() {
        // Typing a known distillery without tapping a suggestion still auto-fills.
        if RegionCatalog.region(id: region) == nil,
           let match = distilleryStore.exactMatch(distilleryName) {
            region = match.region
        }
        guard canSave else { return }

        let target = bottle ?? Bottle()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.distilleryName = distilleryName.trimmingCharacters(in: .whitespaces)
        target.region = region
        target.abv = abv
        target.ageStatement = isNAS ? nil : age
        let trimmedCask = caskType.trimmingCharacters(in: .whitespaces)
        target.caskType = trimmedCask.isEmpty ? nil : trimmedCask
        target.purchasePrice = price
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.status = status
        // Canonical form when it's a real GTIN, so duplicate detection
        // matches the scanner's output; anything else is kept as typed
        // rather than silently discarded.
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespaces)
        target.barcode = Barcode.normalized(trimmedBarcode) ?? (trimmedBarcode.isEmpty ? nil : trimmedBarcode)
        let isNewBottle = bottle == nil
        if isNewBottle {
            // Keep the lookup's stock photo so rows and the detail hero can
            // show it until the owner takes their own (PRD F4).
            target.stockPhotoURL = prefill?.stockPhotoURL
            // The photo captured for label scanning is the best available
            // photo of this exact bottle — save it as the user photo rather
            // than discarding it and going to the internet to search for a
            // stand-in (previously the only outcome of a label scan).
            if let labelPhotoData, let filename = try? imageStore.save(imageData: labelPhotoData) {
                target.userPhotoFilename = filename
            }
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
            dismiss()
            onSaved?()
            // Only worth searching when the bottle still has no photo at
            // all — a barcode-hit stock photo or a label-scan user photo
            // both mean there's nothing to backfill.
            if isNewBottle, target.stockPhotoURL == nil, target.userPhotoFilename == nil {
                stockPhotoBackfill?.fetch(
                    for: target, modelContext: modelContext,
                    distilleryWikipediaTitle: distilleryStore.exactMatch(target.distilleryName)?.wikipediaTitle
                )
            }
        } catch {
            Self.logger.error("Failed to save bottle: \(error)")
        }
    }
}

#Preview {
    BottleFormView(bottle: nil)
        .modelContainer(for: Bottle.self, inMemory: true)
}
