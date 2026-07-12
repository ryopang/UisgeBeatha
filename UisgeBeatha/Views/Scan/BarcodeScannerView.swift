import SwiftUI
import Vision
import VisionKit

/// VisionKit barcode scanner configured for EAN-13 (which also carries
/// UPC-A) per PRD F1. Only usable on a physical device.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> ScannerContainerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .fast,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return ScannerContainerViewController(scanner: scanner)
    }

    func updateUIViewController(_ container: ScannerContainerViewController, context: Context) {
        container.resumeIfNeeded()
    }

    static func dismantleUIViewController(_ container: ScannerContainerViewController, coordinator: Coordinator) {
        container.scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    /// Hosts the DataScannerViewController as a child view controller so we
    /// get reliable `viewDidAppear` / `viewWillDisappear` calls when a sheet
    /// covers and then dismisses this screen. DataScannerViewController
    /// itself can't be subclassed (it's `public`, not `open`), and calling
    /// `startScanning()` from SwiftUI's `updateUIViewController` alone is
    /// unreliable — its timing relative to the view actually appearing in
    /// the window isn't guaranteed, especially right after a sheet's dismiss
    /// animation. This is the hook that makes scanning reliably resume after
    /// Cancel or Save on a sheet, not just on first appearance.
    final class ScannerContainerViewController: UIViewController {
        let scanner: DataScannerViewController

        init(scanner: DataScannerViewController) {
            self.scanner = scanner
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(scanner)
            scanner.view.frame = view.bounds
            scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(scanner.view)
            scanner.didMove(toParent: self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resumeIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            scanner.stopScanning()
        }

        func resumeIfNeeded() {
            guard !scanner.isScanning else { return }
            try? scanner.startScanning()
        }
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
