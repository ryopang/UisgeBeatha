import Foundation

/// Canonical handling for retail barcodes (GTIN-8/12/13/14).
///
/// Two problems this fixes:
/// 1. Manually typed or pasted text went straight into API URL paths
///    (`/product/{barcode}.json`) and cache keys. Anything that isn't a
///    plausible GTIN is now rejected before it reaches the network.
/// 2. VisionKit reports a UPC-A barcode as EAN-13 with a leading zero, but a
///    person typing the digits under the bars enters 12. Without a canonical
///    form, the same bottle could be added twice and duplicate detection
///    would never catch it.
///
/// Check digits are deliberately not enforced: the live scanner already
/// validates them, and a person transcribing a slightly smudged label
/// should still get a lookup attempt rather than a silent refusal.
nonisolated enum Barcode {
    /// Digits only, at a valid GTIN length. A 12-digit UPC-A is padded to
    /// its 13-digit EAN form (what the scanner reports). Returns nil for
    /// anything else.
    static func normalized(_ raw: String) -> String? {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        // Reject input that had letters or symbols mixed in, not just
        // whitespace or dashes a person might type between digit groups.
        let stripped = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == stripped.count else { return nil }
        switch digits.count {
        case 8, 13, 14: return digits
        case 12: return "0" + digits
        default: return nil
        }
    }

    /// Every stored form a canonical barcode might have been saved under
    /// before normalization existed, for duplicate detection: the
    /// canonical EAN-13 plus its 12-digit UPC-A form when it has a leading
    /// zero.
    static func storedVariants(of canonical: String) -> [String] {
        if canonical.count == 13, canonical.hasPrefix("0") {
            return [canonical, String(canonical.dropFirst())]
        }
        return [canonical]
    }
}
