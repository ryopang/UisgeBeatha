import SwiftUI
import VisionKit

/// The live scanner, presented from inside the entry form so a person who
/// landed there after a failed scan can go straight back to scanning —
/// in either mode — instead of being stuck with a still-photo camera and
/// no route back to the barcode reader.
///
/// Barcode mode reports the payload and closes. Label mode accumulates
/// text live and closes when the person accepts what it's read, handing
/// back both the recognized lines and a still frame for the bottle photo.
struct InFormScannerSheet: View {
    let mode: ScanMode
    var onBarcode: (String) -> Void
    var onLabel: ([String], Data?) -> Void

    @Environment(\.distilleryStore) private var distilleryStore
    @Environment(\.expressionStore) private var expressionStore
    @Environment(\.labelOCR) private var labelOCR
    @Environment(\.dismiss) private var dismiss

    @State private var recognizedTextLines: [String] = []
    @State private var liveScanner: DataScannerViewController?

    private var liveLabelResult: LabelScanResult? {
        guard !recognizedTextLines.isEmpty else { return nil }
        return LabelParser.parse(
            lines: recognizedTextLines, distilleryStore: distilleryStore, expressionStore: expressionStore
        )
    }

    var body: some View {
        ZStack {
            LiveScannerView(
                mode: mode,
                onScan: mode == .barcode ? { onBarcode($0) } : nil,
                onTextUpdate: mode == .label ? { recognizedTextLines = $0 } : nil,
                onScannerReady: { liveScanner = $0 }
            )
            .id(mode)
            .ignoresSafeArea()

            VStack {
                Text(mode.instruction)
                    .pillLabel()
                    .padding(.top, 12)
                Spacer()
                if mode == .label {
                    labelAcceptButton
                }
                Button(Strings.Form.cancel, role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
            }
        }
    }

    private var labelAcceptButton: some View {
        Group {
            if let result = liveLabelResult {
                Button {
                    accept(result)
                } label: {
                    VStack(spacing: 2) {
                        Text(Strings.Scan.useThisLabel)
                            .font(.subheadline.weight(Theme.Weight.emphasis))
                        Text(result.name.isEmpty ? result.distilleryName : result.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            } else {
                Text(Strings.Scan.labelReadingNothingYet)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    /// Grabs a still frame so an accepted label read still yields a photo
    /// of the bottle, then hands lines and photo back to the form.
    ///
    /// The captured frame is re-read with the tuned recognizer (see
    /// `ScanView.refinedResult` for why: DataScanner's internal recognition
    /// can't take the seed catalog as `customWords` or turn English
    /// autocorrection off) and its lines are preferred when they resolve a
    /// distillery.
    private func accept(_ result: LabelScanResult) {
        let liveLines = recognizedTextLines
        guard let scanner = liveScanner else {
            onLabel(liveLines, nil)
            return
        }
        Task {
            guard let image = try? await scanner.capturePhoto() else {
                onLabel(liveLines, nil)
                return
            }
            let photoData = image.jpegData(compressionQuality: 0.9)
            if let refinedLines = try? await labelOCR.recognizeText(in: image),
               let refined = LabelParser.parse(
                   lines: refinedLines, distilleryStore: distilleryStore, expressionStore: expressionStore
               ),
               !refined.distilleryName.isEmpty {
                onLabel(refinedLines, photoData)
            } else {
                onLabel(liveLines, photoData)
            }
        }
    }
}
