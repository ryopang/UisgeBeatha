import SwiftUI

/// The hit path (PRD F1): what the lookup found, plus the matched
/// distillery and region. "Add to Collection" opens the entry form
/// pre-filled for confirmation; "Details Only" saves nothing.
struct LookupResultSheet: View {
    let barcode: String
    let product: LookupProduct
    let matchedDistillery: Distillery?

    private var dismiss = ContextualDismiss()
    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.expressionStore) private var expressionStore
    @Environment(\.bottleExtractor) private var bottleExtractor

    @State private var showingAddForm = false
    /// What the on-device model added on top of the heuristics, if it is
    /// available and found anything. Arrives a moment after the sheet
    /// opens; the sheet is fully usable before and without it.
    @State private var enhanced: LabelScanResult?

    /// Neither lookup tier always returns ABV (UPCitemdb never does), and
    /// neither returns an age statement at all, so both fall back to
    /// parsing whatever text the source gave us — the title alone is often
    /// too terse to mention either, so the (usually longer) description is
    /// searched too when the source provides one.
    private var searchableText: [String] {
        [product.name, product.descriptionText].compactMap { $0 }
    }

    private var resolvedABV: Double? {
        product.abv ?? WhiskyLabelParser.abv(in: searchableText) ?? enhanced?.abv
    }

    private var resolvedAge: Int? {
        WhiskyLabelParser.age(in: searchableText) ?? enhanced?.age
    }

    /// The heuristic read, shaped like a label scan so the same merge rules
    /// that guard label scanning guard this too. Heuristic fields are
    /// `confident`, so the model can only fill what they left empty.
    private var heuristicResult: LabelScanResult {
        var result = LabelScanResult()
        result.name = product.name
        result.nameProvenance = .confident
        if let matchedDistillery {
            result.distilleryName = matchedDistillery.name
            result.region = matchedDistillery.region
            result.distilleryProvenance = .confident
        }
        if let abv = product.abv ?? WhiskyLabelParser.abv(in: searchableText) {
            result.abv = abv
            result.abvProvenance = .confident
        }
        if let age = WhiskyLabelParser.age(in: searchableText) {
            result.age = age
            result.ageProvenance = .confident
        }
        return result
    }

    private var prefill: LookupPrefill {
        let modelDistillery = enhanced.flatMap { $0.distilleryName.isEmpty ? nil : $0 }
        return LookupPrefill(
            name: product.name,
            distilleryName: matchedDistillery?.name ?? modelDistillery?.distilleryName ?? product.brand ?? "",
            region: matchedDistillery?.region ?? modelDistillery?.region ?? "",
            abv: resolvedABV,
            age: resolvedAge,
            caskType: enhanced?.cask,
            barcode: barcode,
            stockPhotoURL: product.imageURL
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    productImage
                    VStack(spacing: 6) {
                        Text(product.name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if let brand = product.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if let distillery = matchedDistillery {
                                Text(distillery.name)
                                    .font(.subheadline)
                                RegionTagView(regionID: distillery.region)
                            }
                            if let abv = resolvedABV {
                                Text("\(abv.formatted())%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let age = resolvedAge {
                                Text(Strings.Detail.ageValue(age))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        Button(Strings.Scan.addToCollection) {
                            showingAddForm = true
                        }
                        .buttonStyle(.accentProminent)
                        NavigationLink(Strings.Scan.detailsOnly) {
                            detailsOnlyView
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .task {
                guard enhanced == nil else { return }
                let base = heuristicResult
                enhanced = await bottleExtractor.enhance(
                    base, lines: searchableText,
                    distilleryStore: distilleryStore, expressionStore: expressionStore
                )
            }
            .navigationTitle(Strings.Scan.resultTitle)
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
                    barcodeIsLocked: true,
                    onSaved: { dismiss() }
                )
                // A sheet presented from inside a panel must close itself,
                // not the panel.
                .environment(\.panelDismiss, nil)
            }
        }
    }

    private var productImage: some View {
        Group {
            if let urlString = product.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    imagePlaceholder
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }

    private var imagePlaceholder: some View {
        Image(systemName: "wineglass")
            .font(.largeTitle)
            .imageScale(.large)
            .foregroundStyle(.quaternary)
    }

    /// Read-only view of everything the lookup returned; nothing is saved.
    private var detailsOnlyView: some View {
        List {
            LabeledContent(Strings.Scan.detailsName, value: product.name)
            if let brand = product.brand, !brand.isEmpty {
                LabeledContent(Strings.Scan.detailsBrand, value: brand)
            }
            if let abv = resolvedABV {
                LabeledContent(Strings.Detail.abv, value: "\(abv.formatted())%")
            }
            if let age = resolvedAge {
                LabeledContent(Strings.Detail.age, value: Strings.Detail.ageValue(age))
            }
            LabeledContent(Strings.Form.barcode, value: barcode)
            if let distillery = matchedDistillery {
                LabeledContent(Strings.Detail.distillery, value: distillery.name)
                LabeledContent(
                    Strings.Detail.region,
                    value: RegionCatalog.region(id: distillery.region)?.displayName ?? distillery.region
                )
            }
            if !product.categoryTags.isEmpty {
                LabeledContent(Strings.Scan.detailsCategories, value: product.categoryTags.joined(separator: ", "))
            }
        }
        .navigationTitle(Strings.Scan.detailsOnly)
        .navigationBarTitleDisplayMode(.inline)
    }
}
