import Foundation
import SwiftUI
import Vision

// MARK: - Service

/// Reads a photographed bottle label via on-device text recognition, as a
/// fallback when a barcode lookup misses (PRD F1's miss path otherwise has
/// nothing at all to prefill from). Best-effort only, same philosophy as
/// WhiskyLabelParser: returns raw recognized lines, never anything treated
/// as authoritative — callers still let the person confirm or edit before
/// saving.
protocol LabelOCRServicing: Sendable {
    /// `nonisolated` so the (potentially slow) recognition pass runs off
    /// the main actor regardless of the caller's isolation — the same
    /// class of "camera work quietly blocking the main thread" bug already
    /// hit once this session with the barcode scanner.
    nonisolated func recognizeText(in image: UIImage) async throws -> [String]
}

nonisolated struct VisionLabelOCRService: LabelOCRServicing {
    func recognizeText(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

private extension CGImagePropertyOrientation {
    /// VNImageRequestHandler takes a CGImage, which (unlike UIImage) carries
    /// no orientation of its own — without this, a portrait camera photo
    /// gets read sideways and recognition quality collapses. `nonisolated`
    /// so it can be called from the OCR service's nonisolated (off-main)
    /// recognition pass.
    nonisolated init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Label text to form fields

/// Turns OCR'd label lines into a best-guess prefill, the same shape a
/// barcode-lookup hit produces (PRD F1) — just sourced from a photo instead
/// of a product database. Synchronous so it's testable with plain string
/// fixtures, no Vision or camera involved. Not `nonisolated`: it calls
/// DistilleryStore.bestMatch, which (like the rest of the app) is
/// main-actor isolated by the project's default — this is only ever
/// called from the main actor (the form's OCR handler, or tests) anyway.
enum LabelParser {
    static func parse(lines: [String], distilleryStore: DistilleryStore) -> LookupPrefill? {
        guard !lines.isEmpty else { return nil }

        let matchedDistillery = lines.lazy.compactMap { distilleryStore.bestMatch(for: $0) }.first

        return LookupPrefill(
            name: nameCandidate(in: lines, matching: matchedDistillery) ?? "",
            distilleryName: matchedDistillery?.name ?? "",
            region: matchedDistillery?.region ?? "",
            abv: WhiskyLabelParser.abv(in: lines),
            age: WhiskyLabelParser.age(in: lines)
        )
    }

    /// Prefers the line that names the matched distillery (usually the
    /// product line itself, e.g. "Lagavulin 16 Years Old"); falls back to
    /// the longest recognized line, since a label's most prominent text is
    /// usually the brand/product name.
    private static func nameCandidate(in lines: [String], matching distillery: Distillery?) -> String? {
        if let distillery, let line = lines.first(where: {
            $0.localizedCaseInsensitiveContains(distillery.name)
        }) {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return lines.max { $0.count < $1.count }?.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var labelOCR: any LabelOCRServicing = VisionLabelOCRService()
}

// MARK: - UI-test stub

#if DEBUG
/// Installed when launched with -uiTestLookupStub, matching the other
/// service stubs. The camera itself is still unavailable in the simulator,
/// so this only matters if a future test drives the flow via an injected
/// image rather than the live camera.
struct StubLabelOCRService: LabelOCRServicing {
    nonisolated func recognizeText(in image: UIImage) async throws -> [String] {
        ["Lagavulin 16 Year Old", "Islay Single Malt Scotch Whisky", "43% Vol", "700ml"]
    }
}
#endif
