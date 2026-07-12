import Foundation

/// The scotch-only gate. This object is the one and only place the rule
/// lives (PRD section 10.1); world whisky support later means changing this
/// object's data, nothing else in the scan flow.
struct CollectionPolicy: Sendable {
    /// Countries whose whisky the collection accepts.
    let allowedCountries: Set<String>
    /// Category keywords (e.g. from Open Food Facts tags) that clearly
    /// identify a product as something other than scotch whisky.
    let disallowedCategoryKeywords: Set<String>
    /// Shown when a scanned product is clearly not scotch.
    let rejectionMessage: String

    /// v1 policy: Scotland only.
    static let scotchOnly = CollectionPolicy(
        allowedCountries: ["Scotland"],
        disallowedCategoryKeywords: [
            "bourbon", "irish", "japanese", "canadian", "rye", "tennessee",
            "vodka", "gin", "rum", "wine", "beer", "tequila", "brandy", "cognac",
        ],
        rejectionMessage: Strings.Policy.rejection
    )

    func allows(country: String) -> Bool {
        allowedCountries.contains(country)
    }

    /// True only when category data clearly identifies a non-scotch product.
    /// Ambiguity (no tags, no match) must NOT reject: free databases are too
    /// sparse to trust a hard reject on missing data (PRD F1).
    func clearlyDisallows(categoryTags: [String]) -> Bool {
        categoryTags.contains { tag in
            let lowered = tag.lowercased()
            return disallowedCategoryKeywords.contains { lowered.contains($0) }
        }
    }
}
