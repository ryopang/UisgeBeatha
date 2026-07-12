import SwiftData
import SwiftUI

/// The scan tab (PRD F1): live scanner on device, manual barcode entry
/// where no camera exists (simulator, camera permission denied). Owns the
/// post-capture flow: duplicate check → lookup → gate → result/miss.
struct ScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.barcodeLookup) private var barcodeLookup
    @Environment(\.collectionPolicy) private var collectionPolicy
    @Environment(\.distilleryStore) private var distilleryStore

    @State private var activeSheet: ScanSheet?
    @State private var isLookingUp = false
    @State private var showingRejection = false
    @State private var manualBarcode = ""

    enum ScanSheet: Identifiable {
        case result(LookupResult, LookupProduct)
        case manualEntry(barcode: String)
        case duplicate(Bottle)

        var id: String {
            switch self {
            case .result(let result, _): "result-\(result.barcode)"
            case .manualEntry(let barcode): "manual-\(barcode)"
            case .duplicate(let bottle): "duplicate-\(bottle.id)"
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
                } else if BarcodeScannerView.isSupported {
                    BarcodeScannerView { process(barcode: $0) }
                        .ignoresSafeArea()
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
                        notice: Strings.Scan.missNotice
                    )
                case .duplicate(let bottle):
                    DuplicateBottleSheet(bottle: bottle)
                }
            }
        }
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
                let code = manualBarcode.trimmingCharacters(in: .whitespaces)
                manualBarcode = ""
                process(barcode: code)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualBarcode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(32)
    }

    // MARK: - Flow

    private func process(barcode: String) {
        guard !barcode.isEmpty, !isLookingUp, activeSheet == nil, !showingRejection else { return }

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
        let descriptor = FetchDescriptor<Bottle>(
            predicate: #Predicate { $0.barcode == barcode }
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
    @State private var showingToast = true

    var body: some View {
        NavigationStack {
            BottleDetailView(bottle: bottle)
        }
        .overlay(alignment: .top) {
            if showingToast {
                Text(Strings.Scan.duplicateToast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
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
