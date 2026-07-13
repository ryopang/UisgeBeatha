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
    /// True only for the barcode-miss path: offers a "Scan the Label"
    /// button that reads brand/name/age/ABV off a label photo via OCR.
    var offersLabelScan = false
    /// Called after a successful save, so scan sheets can dismiss the chain.
    var onSaved: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.labelOCR) private var labelOCR
    @Environment(\.dismiss) private var dismiss

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
    @State private var status: BottleStatus
    @State private var barcode: String
    @State private var showingLabelCamera = false
    @State private var isScanningLabel = false
    @State private var labelScanBanner: String?

    @FocusState private var distilleryFieldFocused: Bool

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "BottleForm")

    init(
        bottle: Bottle?,
        prefill: LookupPrefill? = nil,
        barcodeIsLocked: Bool = false,
        notice: String? = nil,
        offersLabelScan: Bool = false,
        onSaved: (() -> Void)? = nil
    ) {
        self.bottle = bottle
        self.prefill = prefill
        self.barcodeIsLocked = barcodeIsLocked
        self.notice = notice
        self.offersLabelScan = offersLabelScan
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
        _status = State(initialValue: bottle?.status ?? .sealed)
        _barcode = State(initialValue: bottle?.barcode ?? prefill?.barcode ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !distilleryName.trimmingCharacters(in: .whitespaces).isEmpty
            && RegionCatalog.region(id: region) != nil
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

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if offersLabelScan, UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showingLabelCamera = true
                            } label: {
                                if isScanningLabel {
                                    Label(Strings.Scan.lookingUp, systemImage: "text.viewfinder")
                                } else {
                                    Label(Strings.Form.scanLabel, systemImage: "text.viewfinder")
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
                    Picker(Strings.Form.status, selection: $status) {
                        ForEach(BottleStatus.allCases, id: \.self) { status in
                            Text(Strings.Status.label(for: status)).tag(status)
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
        .fullScreenCover(isPresented: $showingLabelCamera) {
            CameraPicker { image in
                Task {
                    isScanningLabel = true
                    await applyLabelScan(image)
                    isScanningLabel = false
                }
            }
            .ignoresSafeArea()
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

    /// Applies whatever OCR could read off the label. Only fills fields
    /// that got a new value — never blanks something the person already
    /// typed just because this particular photo didn't confirm it.
    private func applyLabelScan(_ image: UIImage) async {
        do {
            let lines = try await labelOCR.recognizeText(in: image)
            guard let result = LabelParser.parse(lines: lines, distilleryStore: distilleryStore) else {
                labelScanBanner = Strings.Form.labelScanFailure
                return
            }
            if !result.name.isEmpty { name = result.name }
            if !result.distilleryName.isEmpty { distilleryName = result.distilleryName }
            if !result.region.isEmpty { region = result.region }
            if let abv = result.abv { self.abv = abv }
            if let age = result.age {
                self.age = age
                isNAS = false
            }
            labelScanBanner = Strings.Form.labelScanSuccess
        } catch {
            Self.logger.error("Label OCR failed: \(error)")
            labelScanBanner = Strings.Form.labelScanFailure
        }
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
        target.caskType = caskType.isEmpty ? nil : caskType
        target.purchasePrice = price
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.status = status
        target.barcode = barcode.isEmpty ? nil : barcode
        if bottle == nil {
            // Keep the lookup's stock photo so rows and the detail hero can
            // show it until the owner takes their own (PRD F4).
            target.stockPhotoURL = prefill?.stockPhotoURL
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
            dismiss()
            onSaved?()
        } catch {
            Self.logger.error("Failed to save bottle: \(error)")
        }
    }
}

#Preview {
    BottleFormView(bottle: nil)
        .modelContainer(for: Bottle.self, inMemory: true)
}
