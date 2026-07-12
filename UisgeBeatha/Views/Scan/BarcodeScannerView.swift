import SwiftUI
import Vision
import VisionKit

/// VisionKit barcode scanner configured for EAN-13 (which also carries
/// UPC-A) per PRD F1. Only usable on a physical device.
///
/// Restarting a scanning session that's merely been covered by a sheet
/// (rather than removed from the view hierarchy) is unreliable — the
/// camera can come back jittery or stop recognizing barcodes entirely.
/// So this view relies on its caller (ScanView) to fully unmount it
/// whenever any sheet is open, forcing a genuinely fresh instance —
/// SwiftUI's own sizing of a freshly-returned UIViewController's view is
/// what keeps the camera preview correctly framed; don't reintroduce a
/// custom container around this to hook view-lifecycle callbacks without
/// very deliberately re-verifying camera framing on-device.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
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
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var lastPayload: String?

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue,
                      payload != lastPayload else { continue }
                lastPayload = payload
                onScan(payload)
                return
            }
        }
    }
}
