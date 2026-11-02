import Foundation
import Observation

/// What a scan lookup pre-fills into the form (PRD F1 hit and miss paths).
struct LookupPrefill: Sendable {
    var name = ""
    var distilleryName = ""
    var region = ""
    var abv: Double?
    var age: Int?
    var caskType: String?
    var barcode: String?
    var stockPhotoURL: String?
}

/// The staged, editable state behind `BottleFormView`.
///
/// The form edits a draft and only `apply(to:)` touches a real `Bottle`,
/// so Cancel never leaves half-edited data behind. Keeping this out of the
/// view makes validation, label-scan merging and normalization unit
/// testable, and lets the same draft survive the view being rebuilt when
/// the iPhone Duo folds or unfolds mid-edit.
@MainActor @Observable
final class BottleDraft {
    var name: String
    var distilleryName: String
    var region: String
    var abv: Double?
    var isNAS: Bool
    var age: Int?
    var caskType: String
    var price: Decimal?
    var hasPurchaseDate: Bool
    var purchaseDate: Date
    /// nil means "not filled in": a new bottle starts with no status
    /// rather than being silently declared Sealed.
    var status: BottleStatus?
    var barcode: String
    /// A photo already captured for this bottle (from an accepted live
    /// label read). The best available photo of this exact bottle, kept
    /// whether or not OCR could read anything off it.
    var labelPhotoData: Data?
    var labelScanBanner: String?
    /// The lookup's stock photo, carried to the new bottle on save.
    let prefillStockPhotoURL: String?
    let isNewBottle: Bool

    init(bottle: Bottle? = nil, prefill: LookupPrefill? = nil, initialPhotoData: Data? = nil) {
        isNewBottle = bottle == nil
        name = bottle?.name ?? prefill?.name ?? ""
        distilleryName = bottle?.distilleryName ?? prefill?.distilleryName ?? ""
        region = bottle?.region ?? prefill?.region ?? ""
        abv = bottle?.abv ?? prefill?.abv
        isNAS = bottle.map { $0.ageStatement == nil } ?? false
        age = bottle?.ageStatement ?? prefill?.age
        caskType = bottle?.caskType ?? prefill?.caskType ?? ""
        price = bottle?.purchasePrice
        hasPurchaseDate = bottle?.purchaseDate != nil
        purchaseDate = bottle?.purchaseDate ?? .now
        status = bottle?.status
        barcode = bottle?.barcode ?? prefill?.barcode ?? ""
        labelPhotoData = initialPhotoData
        prefillStockPhotoURL = prefill?.stockPhotoURL
    }

    // MARK: - Validation

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !distilleryName.trimmingCharacters(in: .whitespaces).isEmpty
            && RegionCatalog.region(id: region) != nil
            && valuesAreInRange
    }

    /// Guards against typos like "430" for 43% or a negative price, which
    /// the number fields otherwise accept and would then show in the
    /// detail view and exports.
    var valuesAreInRange: Bool {
        (abv.map { (0...100).contains($0) } ?? true)
            && (isNAS || (age.map { (0...100).contains($0) } ?? true))
            && (price.map { $0 >= 0 } ?? true)
    }

    // MARK: - Autocomplete

    /// Seed distilleries whose name contains what's been typed, prefix
    /// matches first. Empty once the field exactly names the only match.
    func distillerySuggestions(in store: DistilleryStore) -> [Distillery] {
        let query = DistilleryStore.normalize(distilleryName)
        guard !query.isEmpty else { return [] }
        let matches = store.distilleries.filter {
            DistilleryStore.normalize($0.name).contains(query)
        }
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
    /// current input: sourced from the person's own data so cask type stays
    /// consistent enough to filter on later.
    func caskTypeSuggestions(from existing: [String?]) -> [String] {
        let allTypes = Set(
            existing.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )
        let query = caskType.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty
            ? allTypes
            : allTypes.filter { $0.localizedCaseInsensitiveContains(query) }
        if matches.count == 1, matches.first?.localizedCaseInsensitiveCompare(query) == .orderedSame {
            return []
        }
        return Array(matches.sorted().prefix(6))
    }

    func select(_ distillery: Distillery) {
        distilleryName = distillery.name
        region = distillery.region
    }

    // MARK: - Label scan

    /// Applies whatever a label scan read. Only fills fields that got a new
    /// value: never blanks something the person already typed just because
    /// this particular read didn't confirm it.
    func applyLabelScan(
        lines: [String], distilleryStore: DistilleryStore, expressionStore: ExpressionStore
    ) {
        guard let result = LabelParser.parse(
            lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
        ) else {
            labelScanBanner = Strings.Form.labelScanFailure
            return
        }
        apply(result)
    }

    /// `applyLabelScan`, then the on-device model's pass on top. The
    /// heuristic result lands immediately; the model only adds to it.
    func applyLabelScan(
        lines: [String], distilleryStore: DistilleryStore, expressionStore: ExpressionStore,
        extractor: any BottleExtracting
    ) async {
        let parsed = LabelParser.parse(
            lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
        )
        if let parsed {
            apply(parsed)
        } else {
            labelScanBanner = Strings.Form.labelScanFailure
        }
        let enhanced = await extractor.enhance(
            parsed, lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
        )
        if let enhanced, enhanced != parsed {
            apply(enhanced)
        }
    }

    func apply(_ result: LabelScanResult) {
        if !result.name.isEmpty { name = result.name }
        if !result.distilleryName.isEmpty { distilleryName = result.distilleryName }
        if !result.region.isEmpty { region = result.region }
        if let abv = result.abv { self.abv = abv }
        if let cask = result.cask, !cask.isEmpty,
           caskType.trimmingCharacters(in: .whitespaces).isEmpty {
            caskType = cask
        }
        if result.isNAS { isNAS = true }
        if let age = result.age {
            self.age = age
            isNAS = false
        }
        labelScanBanner = result.distilleryProvenance == .guessed
            ? Strings.Form.labelScanUncertain
            : Strings.Form.labelScanSuccess
    }

    // MARK: - Commit

    /// Typing a known distillery without tapping a suggestion still
    /// auto-fills the region.
    func resolveRegionIfNeeded(using store: DistilleryStore) {
        if RegionCatalog.region(id: region) == nil,
           let match = store.exactMatch(distilleryName) {
            region = match.region
        }
    }

    /// Writes the draft onto a bottle. Photo handling stays with the
    /// caller, because it is async and goes through the image store.
    func apply(to target: Bottle) {
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
    }
}
