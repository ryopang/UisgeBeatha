import SwiftData
import SwiftUI
import VisionKit

/// The scan tab (PRD F1): live scanner on device, manual barcode entry
/// where no camera exists (simulator, camera permission denied). Owns the
/// post-capture flow: duplicate check → lookup → gate → result/miss.
///
/// The camera runs exactly one recognizer at a time, chosen by an
/// always-visible Barcode/Label switch. An earlier version detected both
/// at once, which meant there was no way to tell what the camera was doing
/// at any given moment — and after a failed barcode attempt, no obvious
/// way back to barcode scanning. One mode, always named on screen.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.barcodeLookup) private var barcodeLookup
    @Environment(\.collectionPolicy) private var collectionPolicy
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.expressionStore) private var expressionStore
    @Environment(\.labelOCR) private var labelOCR

    @AppStorage("scanMode") private var scanModeRawValue = ScanMode.barcode.rawValue

    @State private var activeSheet: ScanSheet?
    @State private var isLookingUp = false
    @State private var showingRejection = false
    @State private var manualBarcode = ""
    /// Accumulated live text from the scanner session. Cleared whenever the
    /// scanner is torn down (mode switch, sheet opening, retake) so a stale
    /// reading never survives into a new session.
    @State private var recognizedTextLines: [String] = []
    /// Held only to grab a still frame when a label read is accepted, so
    /// live label scanning still saves the bottle's photo.
    @State private var liveScanner: DataScannerViewController?

    private var scanMode: ScanMode {
        ScanMode(rawValue: scanModeRawValue) ?? .barcode
    }

    enum ScanSheet: Identifiable {
        case result(LookupResult, LookupProduct)
        case manualEntry(barcode: String)
        case duplicate(Bottle)
        case labelScanResult(LabelScanResult, photoData: Data?)
        /// Plain "I'll enter it myself" escape hatch — no barcode, no
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

    var body: some View {
        NavigationStack {
            Group {
                if showingRejection {
                    rejectionView
                } else if isLookingUp {
                    lookingUpView
                } else if activeSheet != nil {
                    // A sheet is covering the whole screen, so nothing here
                    // is visible — but the branch change still matters: it
                    // tears the scanner fully out of the view tree instead
                    // of merely covering it, releasing the camera session
                    // while the user is on the sheet (a live capture session
                    // sitting behind a Form was causing UI hitches) and
                    // guaranteeing a genuinely fresh scanner, not a resumed
                    // one, once the sheet closes.
                    Color.clear
                } else if LiveScannerView.isSupported {
                    scannerScreen
                } else {
                    manualEntryFallback
                }
            }
            .navigationTitle(Strings.Scan.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .result(let result, let product):
                    LookupResultSheet(
                        barcode: result.barcode,
                        product: product,
                        matchedDistillery: matchDistillery(for: product)
                    )
                case .manualEntry(let barcode):
                    BottleFormView(
                        bottle: nil,
                        prefill: LookupPrefill(barcode: barcode),
                        barcodeIsLocked: true,
                        notice: Strings.Scan.missNotice,
                        offersLabelScan: true
                    )
                case .duplicate(let bottle):
                    DuplicateBottleSheet(bottle: bottle)
                case .labelScanResult(let result, let photoData):
                    LabelScanResultSheet(
                        result: result,
                        capturedPhotoData: photoData,
                        onRetake: {
                            recognizedTextLines = []
                            activeSheet = nil
                        },
                        onSaved: { activeSheet = nil }
                    )
                case .manualForm:
                    BottleFormView(bottle: nil, offersLabelScan: true)
                }
            }
        }
    }

    // MARK: - Scanner

    private var scannerScreen: some View {
        LiveScannerView(
            mode: scanMode,
            onScan: scanMode == .barcode ? { process(barcode: $0) } : nil,
            onTextUpdate: scanMode == .label ? { recognizedTextLines = $0 } : nil,
            onScannerReady: { liveScanner = $0 }
        )
        // recognizedDataTypes is fixed at construction, so a mode change
        // has to build a whole new controller rather than reconfigure one.
        .id(scanMode)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Text(scanMode.instruction)
                .pillLabel()
                .padding(.top, 12)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if scanMode == .label {
                    labelReadout
                }
                modePicker
                Button {
                    activeSheet = .manualForm
                } label: {
                    Text(Strings.Scan.enterManually)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 24)
        }
        // On the whole screen rather than on the picker: switching away
        // and back (label → barcode → label) would otherwise leave the
        // previous session's lines in state, showing a stale "Use This
        // Label" before the new session has read anything.
        .onChange(of: scanMode) {
            recognizedTextLines = []
            liveScanner = nil
        }
    }

    /// The Barcode/Label switch. Always visible, so the current mode is
    /// never in doubt and the other one is always one tap away.
    private var modePicker: some View {
        Picker(Strings.Scan.modePicker, selection: $scanModeRawValue) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.pickerLabel).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
        .padding(6)
        .background(.regularMaterial, in: Capsule())
    }

    /// Live feedback in label mode: what's been read so far, and the
    /// accept button once there's enough to name a distillery.
    private var labelReadout: some View {
        Group {
            if let result = liveLabelResult {
                Button {
                    acceptLabelRead(result)
                } label: {
                    VStack(spacing: 2) {
                        Text(Strings.Scan.useThisLabel)
                            .font(.subheadline.weight(Theme.Weight.emphasis))
                        Text(labelSummary(for: result))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(Strings.Scan.labelReadingNothingYet)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
            }
        }
    }

    /// A cheap re-parse of whatever text has accumulated so far — not a
    /// second recognition pass.
    private var liveLabelResult: LabelScanResult? {
        guard !recognizedTextLines.isEmpty else { return nil }
        return LabelParser.parse(
            lines: recognizedTextLines, distilleryStore: distilleryStore, expressionStore: expressionStore
        )
    }

    private func labelSummary(for result: LabelScanResult) -> String {
        let name = result.name.isEmpty ? result.distilleryName : result.name
        return name.isEmpty ? Strings.Scan.labelReadingNothingYet : name
    }

    /// Grabs a still frame from the live session so the accepted label read
    /// still yields a photo of the bottle, then hands both to the
    /// confirmation sheet.
    ///
    /// The still frame is also re-read with `VisionLabelOCRService`, whose
    /// recognizer is tuned for this specific job (the seed catalog's 292
    /// distillery names as `customWords`, English autocorrection *off* so
    /// names like Bunnahabhain survive, a lowered text-height floor so
    /// small ABV print registers). `DataScannerViewController` does its own
    /// internal recognition with none of that tuning available, so without
    /// this step live scanning would quietly be the less accurate path.
    private func acceptLabelRead(_ liveResult: LabelScanResult) {
        guard let scanner = liveScanner else {
            activeSheet = .labelScanResult(liveResult, photoData: nil)
            return
        }
        Task {
            guard let image = try? await scanner.capturePhoto() else {
                activeSheet = .labelScanResult(liveResult, photoData: nil)
                return
            }
            let photoData = image.jpegData(compressionQuality: 0.9)
            let refined = await Self.refinedResult(
                from: image, using: labelOCR,
                distilleryStore: distilleryStore, expressionStore: expressionStore
            )
            activeSheet = .labelScanResult(refined ?? liveResult, photoData: photoData)
        }
    }

    /// nil when the tuned pass couldn't resolve a distillery — in that case
    /// the live read wins, since it accumulated across many frames rather
    /// than betting everything on one captured moment.
    static func refinedResult(
        from image: UIImage, using labelOCR: any LabelOCRServicing,
        distilleryStore: DistilleryStore, expressionStore: ExpressionStore
    ) async -> LabelScanResult? {
        guard let lines = try? await labelOCR.recognizeText(in: image),
              let result = LabelParser.parse(
                  lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore
              ),
              !result.distilleryName.isEmpty else {
            return nil
        }
        return result
    }

    // MARK: - States

    private var lookingUpView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(Strings.Scan.lookingUp)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var rejectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(Strings.Policy.rejection)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(Strings.Scan.scanAgain) {
                showingRejection = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    /// Simulator / no-camera path; also what the UI driver exercises.
    private var manualEntryFallback: some View {
        VStack(spacing: 20) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(Strings.Scan.cameraUnavailable)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField(Strings.Scan.barcodeField, text: $manualBarcode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Button(Strings.Scan.lookUp) {
                let code = manualBarcode
                manualBarcode = ""
                process(barcode: code)
            }
            .buttonStyle(.borderedProminent)
            // Only a plausible GTIN gets sent to the lookup APIs.
            .disabled(Barcode.normalized(manualBarcode) == nil)
            Button(Strings.Scan.enterManually) {
                activeSheet = .manualForm
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
    }

    // MARK: - Flow

    private func process(barcode rawBarcode: String) {
        // Canonical digits only: nothing else reaches an API URL or the
        // cache, and a UPC-A typed as 12 digits matches its scanned
        // 13-digit form.
        guard let barcode = Barcode.normalized(rawBarcode),
              !isLookingUp, activeSheet == nil, !showingRejection else { return }

        // Duplicate handling: jump to the existing bottle, never add twice.
        if let existing = existingBottle(barcode: barcode) {
            activeSheet = .duplicate(existing)
            return
        }

        isLookingUp = true
        Task {
            let result = await barcodeLookup.lookup(barcode: barcode)
            isLookingUp = false
            switch result.outcome {
            case .hit(let product):
                if collectionPolicy.clearlyDisallows(categoryTags: product.categoryTags) {
                    showingRejection = true
                } else {
                    // Ambiguous data falls through to the result sheet /
                    // form, never a hard reject (PRD F1).
                    activeSheet = .result(result, product)
                }
            case .miss:
                activeSheet = .manualEntry(barcode: barcode)
            }
        }
    }

    private func existingBottle(barcode: String) -> Bottle? {
        // Bottles saved before normalization may hold the 12-digit UPC-A
        // form of the same code.
        let variants = Barcode.storedVariants(of: barcode)
        let canonical = variants[0]
        let legacy = variants.last ?? canonical
        let descriptor = FetchDescriptor<Bottle>(
            predicate: #Predicate { $0.barcode == canonical || $0.barcode == legacy }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func matchDistillery(for product: LookupProduct) -> Distillery? {
        if let match = distilleryStore.bestMatch(for: product.name) {
            return match
        }
        if let brand = product.brand {
            return distilleryStore.bestMatch(for: brand)
        }
        return nil
    }
}

/// Shown when a scanned barcode already exists: the bottle's detail plus
/// an "already in your collection" toast.
private struct DuplicateBottleSheet: View {
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss
    @State private var showingToast = true

    var body: some View {
        NavigationStack {
            BottleDetailView(bottle: bottle)
                // Swipe-to-dismiss alone isn't discoverable, and VoiceOver
                // and Switch Control users need a visible way out.
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.Common.done) { dismiss() }
                    }
                }
        }
        .overlay(alignment: .top) {
            if showingToast {
                Text(Strings.Scan.duplicateToast)
                    .pillLabel()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { showingToast = false }
        }
    }
}
