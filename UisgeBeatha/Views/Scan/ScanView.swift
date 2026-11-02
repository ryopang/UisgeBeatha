import SwiftData
import SwiftUI
import VisionKit

/// The scan tab (PRD F1). Builds the `ScanFlow` from the environment's
/// services once, then hands it to `ScanScreen`. The flow outlives view
/// rebuilds, so a size-class change (folding the iPhone Duo) never drops a
/// lookup in progress or an open result.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.barcodeLookup) private var barcodeLookup
    @Environment(\.collectionPolicy) private var collectionPolicy
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.expressionStore) private var expressionStore
    @Environment(\.labelOCR) private var labelOCR

    @State private var flow: ScanFlow?

    var body: some View {
        Group {
            if let flow {
                ScanScreen(flow: flow)
            } else {
                Color.clear
            }
        }
        .task {
            if flow == nil { flow = makeFlow() }
        }
    }

    private func makeFlow() -> ScanFlow {
        let context = modelContext
        return ScanFlow(
            lookup: barcodeLookup,
            policy: collectionPolicy,
            labelOCR: labelOCR,
            distilleryStore: distilleryStore,
            expressionStore: expressionStore,
            findExistingBottle: { barcode in Self.existingBottle(barcode: barcode, in: context) }
        )
    }

    static func existingBottle(barcode: String, in context: ModelContext) -> Bottle? {
        // Bottles saved before normalization may hold the 12-digit UPC-A
        // form of the same code.
        let variants = Barcode.storedVariants(of: barcode)
        let canonical = variants[0]
        let legacy = variants.last ?? canonical
        let descriptor = FetchDescriptor<Bottle>(
            predicate: #Predicate { $0.barcode == canonical || $0.barcode == legacy }
        )
        return (try? context.fetch(descriptor))?.first
    }
}

/// The scan screen itself: live scanner on device, manual barcode entry
/// where no camera exists (simulator, camera permission denied).
///
/// The camera runs exactly one recognizer at a time, chosen by an
/// always-visible Barcode/Label switch. An earlier version detected both
/// at once, which meant there was no way to tell what the camera was doing
/// at any given moment, and after a failed barcode attempt, no obvious
/// way back to barcode scanning. One mode, always named on screen.
private struct ScanScreen: View {
    @Bindable var flow: ScanFlow

    @Environment(\.distilleryStore) private var distilleryStore

    @AppStorage("scanMode") private var scanModeRawValue = ScanMode.barcode.rawValue

    @State private var manualBarcode = ""
    /// Held only to grab a still frame when a label read is accepted, so
    /// live label scanning still saves the bottle's photo.
    @State private var liveScanner: DataScannerViewController?

    private var scanMode: ScanMode {
        ScanMode(rawValue: scanModeRawValue) ?? .barcode
    }

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .rejected:
                    rejectionView
                case .lookingUp:
                    lookingUpView
                case .scanning:
                    if flow.sheet != nil {
                        // A sheet is covering the whole screen, so nothing
                        // here is visible, but the branch change still
                        // matters: it tears the scanner fully out of the
                        // view tree instead of merely covering it,
                        // releasing the camera session while the person is
                        // on the sheet and guaranteeing a genuinely fresh
                        // scanner, not a resumed one, once the sheet closes.
                        Color.clear
                    } else if LiveScannerView.isSupported {
                        scannerScreen
                    } else {
                        manualEntryFallback
                    }
                }
            }
            .navigationTitle(Strings.Scan.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $flow.sheet) { sheet in
                sheetContent(sheet)
            }
            // Nothing read in a previous scanner session applies to the
            // next one: a stale "Use This Label" must never survive a sheet
            // opening or a mode switch.
            .onChange(of: flow.isScannerSuspended) { _, suspended in
                if suspended {
                    flow.resetLiveReading()
                    liveScanner = nil
                }
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ScanFlow.Sheet) -> some View {
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
                onRetake: { flow.retakeLabel() },
                onSaved: { flow.sheet = nil }
            )
        case .manualForm:
            BottleFormView(bottle: nil, offersLabelScan: true)
        }
    }

    // MARK: - Scanner

    private var scannerScreen: some View {
        LiveScannerView(
            mode: scanMode,
            onScan: scanMode == .barcode ? { flow.process(barcode: $0) } : nil,
            onTextUpdate: scanMode == .label ? { flow.labelReader.update(lines: $0) } : nil,
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
                    flow.presentManualForm()
                } label: {
                    Text(Strings.Scan.enterManually)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 24)
        }
        // On the whole screen rather than on the picker: switching away
        // and back (label, barcode, label) would otherwise leave the
        // previous session's lines in state, showing a stale "Use This
        // Label" before the new session has read anything.
        .onChange(of: scanMode) {
            flow.resetLiveReading()
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
            if let result = flow.labelReader.result {
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
                    .frame(minHeight: 44)
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

    private func labelSummary(for result: LabelScanResult) -> String {
        let name = result.name.isEmpty ? result.distilleryName : result.name
        return name.isEmpty ? Strings.Scan.labelReadingNothingYet : name
    }

    /// Grabs a still frame from the live session so the accepted label
    /// read still yields a photo of the bottle; the flow re-reads it with
    /// the tuned recognizer and presents the confirmation.
    private func acceptLabelRead(_ liveResult: LabelScanResult) {
        let scanner = liveScanner
        Task {
            var image: UIImage?
            if let scanner {
                image = try? await scanner.capturePhoto()
            }
            await flow.acceptLabelRead(live: liveResult, capturedImage: image)
        }
    }

    // MARK: - States

    private var lookingUpView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(Strings.Scan.lookingUp)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(Strings.Scan.cancelLookup) {
                flow.cancelLookup()
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
    }

    private var rejectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text(Strings.Policy.rejection)
                .font(.headline)
                .multilineTextAlignment(.center)
            Button(Strings.Scan.scanAgain) {
                flow.dismissRejection()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    /// Simulator / no-camera path; also what the UI driver exercises.
    private var manualEntryFallback: some View {
        VStack(spacing: 20) {
            Image(systemName: "barcode.viewfinder")
                .font(.largeTitle)
                .imageScale(.large)
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
                flow.process(barcode: code)
            }
            .buttonStyle(.borderedProminent)
            // Only a plausible GTIN gets sent to the lookup APIs.
            .disabled(Barcode.normalized(manualBarcode) == nil)
            Button(Strings.Scan.enterManually) {
                flow.presentManualForm()
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
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
