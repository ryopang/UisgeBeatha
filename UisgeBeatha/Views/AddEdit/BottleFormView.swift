import OSLog
import SwiftData
import SwiftUI

/// Manual entry and edit form (PRD F2). Pass nil to create a new bottle.
/// Edits are staged in local state and only applied on Save, so Cancel
/// never leaves half-edited data behind.
struct BottleFormView: View {
    let bottle: Bottle?
    /// True when the barcode came from a scan and must not be edited.
    var barcodeIsLocked = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.distilleryStore) private var distilleryStore
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

    @FocusState private var distilleryFieldFocused: Bool

    private static let logger = Logger(subsystem: "com.ryo.UisgeBeatha", category: "BottleForm")

    init(bottle: Bottle?, barcodeIsLocked: Bool = false) {
        self.bottle = bottle
        self.barcodeIsLocked = barcodeIsLocked
        _name = State(initialValue: bottle?.name ?? "")
        _distilleryName = State(initialValue: bottle?.distilleryName ?? "")
        _region = State(initialValue: bottle?.region ?? "")
        _abv = State(initialValue: bottle?.abv)
        _isNAS = State(initialValue: bottle.map { $0.ageStatement == nil } ?? false)
        _age = State(initialValue: bottle?.ageStatement)
        _caskType = State(initialValue: bottle?.caskType ?? "")
        _price = State(initialValue: bottle?.purchasePrice)
        _hasPurchaseDate = State(initialValue: bottle?.purchaseDate != nil)
        _purchaseDate = State(initialValue: bottle?.purchaseDate ?? .now)
        _status = State(initialValue: bottle?.status ?? .sealed)
        _barcode = State(initialValue: bottle?.barcode ?? "")
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
            modelContext.insert(target)
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            Self.logger.error("Failed to save bottle: \(error)")
        }
    }
}

#Preview {
    BottleFormView(bottle: nil)
        .modelContainer(for: Bottle.self, inMemory: true)
}
