import Foundation
import Observation
import UIKit

/// The post-capture flow behind the Scan tab: duplicate check, lookup,
/// scotch gate, and which sheet or panel to show next.
///
/// This used to live inside `ScanView`, which made it untestable and tied
/// the flow to sheet presentation. As a flow model it can be driven by a
/// compact-width sheet or by the iPhone Duo's trailing panel with no
/// change.
@MainActor @Observable
final class ScanFlow {
    enum Phase: Equatable {
        case scanning
        case lookingUp
        /// A clearly non-scotch product was scanned.
        case rejected
    }

    /// What the flow wants shown over the scanner.
    enum Sheet: Identifiable {
        case result(LookupResult, LookupProduct)
        case manualEntry(barcode: String)
        case duplicate(Bottle)
        case labelScanResult(LabelScanResult, photoData: Data?)
        /// Plain "I'll enter it myself" escape hatch: no barcode, no
        /// notice, nothing pre-filled. Distinct from `.manualEntry`, which
        /// implies a lookup was actually attempted and missed.
        case manualForm

        var id: String {
            switch self {
            case .result(let result, _): "result-\(result.barcode)"
            case .manualEntry(let barcode): "manual-\(barcode)"
            case .duplicate(let bottle): "duplicate-\(bottle.id)"
            case .labelScanResult: "label-scan-result"
            case .manualForm: "manual-form"
            }
        }
    }

    private(set) var phase: Phase = .scanning
    var sheet: Sheet?
    /// True in the regular-width layout, where results appear in a trailing
    /// panel beside the camera rather than over it. The camera then stays
    /// live (scans are still ignored while a lookup or result is open).
    var showsResultsBesideScanner = false
    let labelReader: LiveLabelReader

    @ObservationIgnored private let lookup: any BarcodeLookupServicing
    @ObservationIgnored private let policy: CollectionPolicy
    @ObservationIgnored private let labelOCR: any LabelOCRServicing
    @ObservationIgnored private let extractor: any BottleExtracting
    @ObservationIgnored private let distilleryStore: DistilleryStore
    @ObservationIgnored private let expressionStore: ExpressionStore
    @ObservationIgnored private let findExistingBottle: (String) -> Bottle?
    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var lastRequestedBarcode: String?
    /// After a cancel the barcode is usually still in front of the camera;
    /// without this the freshly remounted scanner would read it again at
    /// once and start the same lookup the person just abandoned.
    @ObservationIgnored private var suppressed: (barcode: String, until: Date)?

    static let cancelSuppression: TimeInterval = 4

    init(
        lookup: any BarcodeLookupServicing,
        policy: CollectionPolicy,
        labelOCR: any LabelOCRServicing,
        extractor: any BottleExtracting = NoOpBottleExtractor(),
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore,
        findExistingBottle: @escaping (String) -> Bottle?
    ) {
        self.lookup = lookup
        self.policy = policy
        self.labelOCR = labelOCR
        self.extractor = extractor
        self.distilleryStore = distilleryStore
        self.expressionStore = expressionStore
        self.findExistingBottle = findExistingBottle
        self.labelReader = LiveLabelReader(
            distilleryStore: distilleryStore, expressionStore: expressionStore
        )
    }

    /// True while the scanner view should be unmounted: a lookup, a
    /// rejection or any presented sheet owns the screen. Tearing the camera
    /// fully down (not merely pausing it) is what makes it come back
    /// reliably.
    var isScannerSuspended: Bool {
        !showsResultsBesideScanner && (phase != .scanning || sheet != nil)
    }

    // MARK: - Barcode

    func process(barcode rawBarcode: String, now: Date = .now) {
        // Canonical digits only: nothing else reaches an API URL or the
        // cache, and a UPC-A typed as 12 digits matches its scanned
        // 13-digit form.
        guard let barcode = Barcode.normalized(rawBarcode),
              phase == .scanning, sheet == nil else { return }
        if let suppressed, suppressed.barcode == barcode, now < suppressed.until { return }

        // Duplicate handling: jump to the existing bottle, never add twice.
        if let existing = findExistingBottle(barcode) {
            sheet = .duplicate(existing)
            return
        }

        phase = .lookingUp
        lastRequestedBarcode = barcode
        lookupTask = Task { [lookup] in
            let result = await lookup.lookup(barcode: barcode)
            guard !Task.isCancelled else { return }
            self.finishLookup(result)
        }
    }

    private func finishLookup(_ result: LookupResult) {
        lookupTask = nil
        phase = .scanning
        switch result.outcome {
        case .hit(let product):
            if policy.clearlyDisallows(categoryTags: product.categoryTags) {
                phase = .rejected
            } else {
                // Ambiguous data falls through to the result sheet / form,
                // never a hard reject (PRD F1).
                Haptics.success()
                sheet = .result(result, product)
            }
        case .miss:
            sheet = .manualEntry(barcode: result.barcode)
        }
    }

    /// The "Looking up…" Cancel button. With 12 s timeouts per tier the
    /// worst case is about 25 s, which deserves an exit.
    func cancelLookup(now: Date = .now) {
        guard phase == .lookingUp else { return }
        lookupTask?.cancel()
        lookupTask = nil
        phase = .scanning
        if let barcode = lastRequestedBarcode {
            suppressed = (barcode, now.addingTimeInterval(Self.cancelSuppression))
        }
    }

    func dismissRejection() {
        if phase == .rejected { phase = .scanning }
    }

    // MARK: - Label

    /// The accepted live read, with the still frame grabbed at that
    /// moment (nil if the capture failed). Re-reads the frame with the
    /// tuned recognizer and presents the confirmation.
    func acceptLabelRead(live: LabelScanResult, capturedImage: UIImage?) async {
        guard let capturedImage else {
            sheet = .labelScanResult(live, photoData: nil)
            return
        }
        async let photoData = LabelRefinement.jpegData(from: capturedImage)
        let refined = await LabelRefinement.refine(
            image: capturedImage, using: labelOCR,
            distilleryStore: distilleryStore, expressionStore: expressionStore
        )
        let base = refined?.result ?? live
        // The on-device model fills gaps the heuristics left, within the
        // merge rules and a time budget; with no model this is `base`.
        let enhanced = await extractor.enhance(
            base, lines: refined?.lines ?? labelReader.lines,
            distilleryStore: distilleryStore, expressionStore: expressionStore
        )
        Haptics.success()
        sheet = .labelScanResult(enhanced ?? base, photoData: await photoData)
    }

    /// Warms the on-device model when label mode opens, so "Use This
    /// Label" doesn't pay the model's cold start.
    func prewarmExtractor() {
        extractor.prewarm()
    }

    /// "Retake" from the label confirmation: back to a fresh scanner.
    func retakeLabel() {
        labelReader.reset()
        sheet = nil
    }

    func presentManualForm() {
        sheet = .manualForm
    }

    /// The scan mode changed or the scanner was torn down: nothing read in
    /// the previous session applies to the next one.
    func resetLiveReading() {
        labelReader.reset()
    }
}
