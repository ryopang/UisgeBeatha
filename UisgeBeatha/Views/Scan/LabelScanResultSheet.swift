import SwiftUI

/// The label-scan confirmation step (L5): shown after a live label scan
/// resolves something, before the entry form ever opens. Structurally
/// parallel to `LookupResultSheet` (the barcode-hit equivalent) so the two
/// scan paths feel like one feature rather than two.
///
/// With a pipeline that's sometimes wrong (measured at 5/12 all-fields
/// correct before the L1 rewrite, ~98% after on the fixture corpus — see
/// docs/label-scan-plan.md), silently overwriting form fields and hoping
/// was the wrong shape. Every field here shows whether it was read
/// confidently, guessed, or not found at all, and a low-confidence
/// distillery match can be corrected in two taps before anything is saved.
struct LabelScanResultSheet: View {
    let result: LabelScanResult
    /// A still frame grabbed from the live session at the moment this read
    /// was accepted — the best available photo of this exact bottle, so
    /// the scan doesn't end with the app going to the internet looking for
    /// a stand-in for a bottle the person was just pointing a camera at.
    var capturedPhotoData: Data?
    var onRetake: () -> Void
    var onSaved: (() -> Void)?

    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var distilleryName: String
    @State private var region: String
    @State private var showingAddForm = false
    @State private var showingDistilleryPicker = false

    init(
        result: LabelScanResult,
        capturedPhotoData: Data? = nil,
        onRetake: @escaping () -> Void,
        onSaved: (() -> Void)? = nil
    ) {
        self.result = result
        self.capturedPhotoData = capturedPhotoData
        self.onRetake = onRetake
        self.onSaved = onSaved
        _distilleryName = State(initialValue: result.distilleryName)
        _region = State(initialValue: result.region)
    }

    /// True once the person has corrected the distillery in the picker —
    /// from that point it reads as confident, since it's no longer a guess.
    private var distilleryWasEdited: Bool {
        distilleryName != result.distilleryName
    }

    private var prefill: LookupPrefill {
        LookupPrefill(
            name: result.name, distilleryName: distilleryName, region: region,
            abv: result.abv, age: result.isNAS ? nil : result.age
        )
    }

    private var hasAnyUncertainField: Bool {
        !distilleryWasEdited
            && [result.distilleryProvenance, result.ageProvenance, result.abvProvenance].contains(.guessed)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let capturedPhotoData, let image = UIImage(data: capturedPhotoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                            .frame(height: 72)
                            .accessibilityHidden(true)
                    }
                    Text(result.name.isEmpty ? Strings.ScanResult.title : result.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    fieldsCard

                    if hasAnyUncertainField {
                        Label(Strings.ScanResult.confidenceCaption, systemImage: "questionmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 12) {
                        Button(Strings.Scan.addToCollection) {
                            showingAddForm = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button(Strings.ScanResult.retake, role: .cancel) {
                            onRetake()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(Strings.ScanResult.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Collection.cancel, role: .cancel) { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddForm) {
                BottleFormView(
                    bottle: nil,
                    prefill: prefill,
                    initialPhotoData: capturedPhotoData,
                    onSaved: {
                        onSaved?()
                        dismiss()
                    }
                )
            }
            .sheet(isPresented: $showingDistilleryPicker) {
                DistilleryPickerSheet(
                    distilleryStore: distilleryStore,
                    suggested: result.alternateDistilleries
                ) { selected in
                    distilleryName = selected.name
                    region = selected.region
                    showingDistilleryPicker = false
                }
            }
        }
    }

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            fieldRow(
                label: Strings.Detail.distillery,
                value: distilleryName.isEmpty ? nil : distilleryName,
                provenance: distilleryWasEdited ? .confident : result.distilleryProvenance,
                action: { showingDistilleryPicker = true }
            )
            Divider()
            fieldRow(
                label: Strings.Detail.region,
                value: RegionCatalog.region(id: region)?.displayName,
                provenance: distilleryWasEdited ? .confident : result.distilleryProvenance
            )
            Divider()
            fieldRow(
                label: Strings.Detail.age,
                value: result.isNAS ? Strings.Detail.nas : result.age.map(Strings.Detail.ageValue),
                provenance: result.ageProvenance
            )
            Divider()
            fieldRow(
                label: Strings.Detail.abv,
                value: result.abv.map { "\($0.formatted())%" },
                provenance: result.abvProvenance
            )
        }
        .cardBackground()
    }

    private func fieldRow(
        label: String, value: String?, provenance: FieldProvenance, action: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text(value ?? Strings.ScanResult.notFound)
                    .foregroundStyle(value == nil ? .tertiary : .primary)
                if provenance == .guessed {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value ?? Strings.ScanResult.notFound)\(provenance == .guessed ? ", \(Strings.ScanResult.guessedLabel)" : "")")
        .accessibilityAddTraits(action != nil ? .isButton : [])
    }
}

/// Full-screen searchable distillery picker, opened from the distillery
/// field row above when its match is uncertain (or just to correct it).
/// Shows the parser's own runner-up candidates first when it has any.
private struct DistilleryPickerSheet: View {
    let distilleryStore: DistilleryStore
    let suggested: [Distillery]
    let onSelect: (Distillery) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var searchResults: [Distillery] {
        guard !query.isEmpty else { return [] }
        let normalized = DistilleryStore.normalize(query)
        return distilleryStore.distilleries
            .filter { DistilleryStore.normalize($0.name).contains(normalized) }
            .sorted { $0.name < $1.name }
    }

    private var allSorted: [Distillery] {
        distilleryStore.distilleries.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !suggested.isEmpty {
                    Section(Strings.ScanResult.suggestedDistilleries) {
                        ForEach(suggested) { row(for: $0) }
                    }
                }
                Section(query.isEmpty ? Strings.ScanResult.allDistilleries : Strings.ScanResult.searchResults) {
                    ForEach(query.isEmpty ? allSorted : searchResults) { row(for: $0) }
                }
            }
            .searchable(text: $query, prompt: Strings.ScanResult.searchDistilleries)
            .navigationTitle(Strings.Detail.distillery)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Collection.cancel, role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func row(for distillery: Distillery) -> some View {
        Button {
            onSelect(distillery)
        } label: {
            HStack {
                Text(distillery.name)
                    .foregroundStyle(.primary)
                Spacer()
                RegionTagView(regionID: distillery.region)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
