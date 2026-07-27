import Foundation

/// What the live camera session is currently recognizing.
///
/// Deliberately explicit rather than "recognize everything at once". A
/// single session that silently detected both barcodes and label text left
/// no way to tell what the camera was actually doing at any moment, and no
/// way to get *back* to barcode scanning once a label attempt had started.
/// One mode at a time, always named on screen, always switchable.
enum ScanMode: String, CaseIterable, Identifiable, Sendable {
    case barcode
    case label

    var id: String { rawValue }

    var pickerLabel: String {
        switch self {
        case .barcode: Strings.Scan.modeBarcode
        case .label: Strings.Scan.modeLabel
        }
    }

    /// The one-line "what to point the camera at" hint shown over the feed.
    var instruction: String {
        switch self {
        case .barcode: Strings.Scan.barcodeInstruction
        case .label: Strings.Scan.labelInstruction
        }
    }
}
