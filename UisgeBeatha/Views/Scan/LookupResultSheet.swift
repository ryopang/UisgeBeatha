import SwiftUI

/// The hit path (PRD F1): what the lookup found, plus the matched
/// distillery and region. "Add to Collection" opens the entry form
/// pre-filled for confirmation; "Details Only" saves nothing.
struct LookupResultSheet: View {
    let barcode: String
    let product: LookupProduct
    let matchedDistillery: Distillery?

    @Environment(\.dismiss) private var dismiss
    @State private var showingAddForm = false

    /// Neither lookup tier always returns ABV (UPCitemdb never does), and
    /// neither returns an age statement at all, so both fall back to
    /// parsing whatever text the source gave us — the title alone is often
    /// too terse to mention either, so the (usually longer) description is
    /// searched too when the source provides one.
    private var searchableText: [String] {
        [product.name, product.descriptionText].compactMap { $0 }
    }

    private var resolvedABV: Double? {
        product.abv ?? WhiskyLabelParser.abv(in: searchableText)
    }

    private var resolvedAge: Int? {
        WhiskyLabelParser.age(in: searchableText)
    }

    private var prefill: LookupPrefill {
        LookupPrefill(
            name: product.name,
            distilleryName: matchedDistillery?.name ?? product.brand ?? "",
            region: matchedDistillery?.region ?? "",
            abv: resolvedABV,
            age: resolvedAge,
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
                        .buttonStyle(.borderedProminent)
                        NavigationLink(Strings.Scan.detailsOnly) {
                            detailsOnlyView
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
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
            .font(.system(size: 56))
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
