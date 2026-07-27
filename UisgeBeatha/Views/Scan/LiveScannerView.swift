import SwiftUI
import Vision
import VisionKit

/// The live VisionKit camera session, running exactly one recognizer at a
/// time (see `ScanMode`). Only usable on a physical device.
///
/// `recognizedDataTypes` is fixed at construction by
/// `DataScannerViewController`, so switching mode means a genuinely new
/// controller — callers must key this view on the mode (`.id(mode)`) so
/// SwiftUI rebuilds it rather than trying to reconfigure one in place.
///
/// Restarting a scanning session that's merely been covered by a sheet
/// (rather than removed from the view hierarchy) is unreliable — the
/// camera can come back jittery or stop recognizing entirely. So this view
/// relies on its caller to fully unmount it whenever any sheet is open,
/// forcing a genuinely fresh instance — SwiftUI's own sizing of a
/// freshly-returned UIViewController's view is what keeps the camera
/// preview correctly framed; don't reintroduce a custom container around
/// this to hook view-lifecycle callbacks without very deliberately
/// re-verifying camera framing on-device.
struct LiveScannerView: UIViewControllerRepresentable {
    let mode: ScanMode
    /// Fires once per distinct barcode payload. Only in `.barcode` mode.
    var onScan: ((String) -> Void)?
    /// Every recognized text line whenever the live text changes (a new
    /// line, or an existing line's transcript refined by a later frame).
    /// Lines are in Vision's own order, deduplicated by recognized-item
    /// identity — a line whose transcript is later revised updates in
    /// place rather than appending a stale duplicate. Only in `.label` mode.
    var onTextUpdate: (([String]) -> Void)?
    /// Handed the live controller so the caller can grab a still frame
    /// (`capturePhoto()`) at the moment the person accepts a label read —
    /// that frame becomes the bottle's photo, so live scanning doesn't
    /// lose the "keep the photo you just took" behaviour that the old
    /// still-camera label flow had.
    var onScannerReady: ((DataScannerViewController) -> Void)?

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let dataTypes: Set<DataScannerViewController.RecognizedDataType> = switch mode {
        case .barcode: [.barcode(symbologies: [.ean13, .ean8])]
        case .label: [.text(languages: ["en-GB", "en-US"])]
        }
        let scanner = DataScannerViewController(
            recognizedDataTypes: dataTypes,
            qualityLevel: .fast,
            // A label has several lines on screen at once; a barcode scan
            // only ever wants the one.
            recognizesMultipleItems: mode == .label,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        onScannerReady?(scanner)
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onTextUpdate: onTextUpdate)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: ((String) -> Void)?
        let onTextUpdate: (([String]) -> Void)?
        private var lastBarcodePayload: String?
        /// Ordered by first-seen so line-window pairing downstream
        /// (LabelParser) sees a stable, sensible sequence rather than
        /// whatever order a Set or a dictionary would produce.
        private var textItemOrder: [UUID] = []
        private var textByItemID: [UUID: String] = [:]

        init(onScan: ((String) -> Void)?, onTextUpdate: (([String]) -> Void)?) {
            self.onScan = onScan
            self.onTextUpdate = onTextUpdate
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            handle(updatedItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            var textChanged = false
            for item in items {
                switch item {
                case .barcode(let barcode):
                    guard let payload = barcode.payloadStringValue, payload != lastBarcodePayload else { continue }
                    lastBarcodePayload = payload
                    onScan?(payload)
                case .text(let text):
                    let transcript = text.transcript
                    guard !transcript.isEmpty else { continue }
                    if textByItemID[item.id] != transcript {
                        if textByItemID[item.id] == nil { textItemOrder.append(item.id) }
                        textByItemID[item.id] = transcript
                        textChanged = true
                    }
                @unknown default:
                    break
                }
            }
            if textChanged {
                onTextUpdate?(textItemOrder.compactMap { textByItemID[$0] })
            }
        }
    }
}
