import Foundation
import Observation
import UIKit

/// Turns the live camera's accumulating text lines into a parsed label,
/// off the main actor and throttled.
///
/// `DataScannerViewController` reports text updates many times a second.
/// Parsing windowed fuzzy matches against 126 distilleries on every update,
/// on the main thread, competes with the camera preview for frames. This
/// coalesces bursts into at most one parse per `interval` and runs the
/// parse on a background thread; the newest lines always win.
@MainActor @Observable
final class LiveLabelReader {
    /// About 4 Hz.
    static let interval: Duration = .milliseconds(250)

    /// Everything the camera has read so far this session.
    private(set) var lines: [String] = []
    /// The latest completed parse of `lines`, nil until something parses.
    private(set) var result: LabelScanResult?

    @ObservationIgnored private let distilleryStore: DistilleryStore
    @ObservationIgnored private let expressionStore: ExpressionStore
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore,
        interval: Duration = LiveLabelReader.interval
    ) {
        self.distilleryStore = distilleryStore
        self.expressionStore = expressionStore
        self.interval = interval
    }

    /// Records the newest lines and schedules a parse unless one is already
    /// waiting (it will pick these lines up when it runs).
    func update(lines newLines: [String]) {
        lines = newLines
        guard pending == nil else { return }
        pending = Task { await self.runScheduledParse() }
    }

    /// Clears state when a scan session ends, so a stale reading never
    /// survives into the next one.
    func reset() {
        pending?.cancel()
        pending = nil
        lines = []
        result = nil
    }

    private func runScheduledParse() async {
        try? await Task.sleep(for: interval)
        guard !Task.isCancelled else { return }

        let snapshot = lines
        let distilleries = distilleryStore
        let expressions = expressionStore
        var parsed: LabelScanResult?
        if !snapshot.isEmpty {
            parsed = await Task.detached(priority: .userInitiated) {
                LabelParser.parse(lines: snapshot, distilleryStore: distilleries, expressionStore: expressions)
            }.value
        }
        guard !Task.isCancelled else { return }

        result = parsed
        pending = nil
        // More text arrived while parsing: go again with the newest.
        if lines != snapshot {
            update(lines: lines)
        }
    }
}

/// The accepted-frame step shared by the Scan tab and the in-form scanner.
///
/// `DataScannerViewController` does its own recognition with none of the
/// tuning available (the seed catalog as `customWords`, English
/// autocorrection off so names like Bunnahabhain survive, a lowered
/// text-height floor so small ABV print registers). Re-reading the captured
/// still with `VisionLabelOCRService` keeps the live path from being the
/// less accurate one.
nonisolated enum LabelRefinement {
    struct Refined: Sendable {
        let lines: [String]
        let result: LabelScanResult
    }

    /// nil when the tuned pass couldn't resolve a distillery. The live read
    /// wins then, since it accumulated across many frames rather than
    /// betting everything on one captured moment.
    static func refine(
        image: UIImage,
        using labelOCR: any LabelOCRServicing,
        distilleryStore: DistilleryStore,
        expressionStore: ExpressionStore
    ) async -> Refined? {
        guard let lines = try? await labelOCR.recognizeText(in: image) else { return nil }
        let parsed = await Task.detached(priority: .userInitiated) {
            LabelParser.parse(lines: lines, distilleryStore: distilleryStore, expressionStore: expressionStore)
        }.value
        guard let parsed, !parsed.distilleryName.isEmpty else { return nil }
        return Refined(lines: lines, result: parsed)
    }

    /// JPEG encode of a full camera frame, off the main actor.
    static func jpegData(from image: UIImage) async -> Data? {
        await PhotoEncoder.jpegDataOffMain(from: image)
    }
}
