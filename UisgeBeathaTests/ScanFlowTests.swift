import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 1: the scan flow as a plain model, with no camera and no UI.
@MainActor
struct ScanFlowTests {
    final class FakeLookup: BarcodeLookupServicing {
        var outcome: LookupOutcome = .miss
        var delay: Duration = .zero
        private(set) var calls: [String] = []

        func lookup(barcode: String) async -> LookupResult {
            calls.append(barcode)
            if delay > .zero { try? await Task.sleep(for: delay) }
            return LookupResult(barcode: barcode, outcome: outcome, source: "Fake")
        }
    }

    private let scotch = LookupProduct(
        name: "Lagavulin 16", brand: "Lagavulin", categoryTags: ["en:scotch-whisky"]
    )
    private let bourbon = LookupProduct(
        name: "Frontier Bourbon", brand: "Frontier", categoryTags: ["en:bourbon-whiskey"]
    )
    private let barcode = "5000281005416"

    private func makeFlow(
        _ lookup: FakeLookup, existing: [String: Bottle] = [:]
    ) -> ScanFlow {
        ScanFlow(
            lookup: lookup,
            policy: .scotchOnly,
            labelOCR: StubLabelOCRService(),
            distilleryStore: DistilleryStore(distilleries: []),
            expressionStore: ExpressionStore(expressions: []),
            findExistingBottle: { existing[$0] }
        )
    }

    @Test func hitPresentsResultSheet() async {
        let lookup = FakeLookup()
        lookup.outcome = .hit(scotch)
        let flow = makeFlow(lookup)

        flow.process(barcode: barcode)
        #expect(flow.phase == .lookingUp)
        #expect(flow.isScannerSuspended)

        #expect(await waitUntil { flow.sheet != nil })
        guard case .result(let result, let product) = flow.sheet else {
            Issue.record("Expected a result sheet")
            return
        }
        #expect(result.barcode == barcode)
        #expect(product == scotch)
        #expect(flow.phase == .scanning)
    }

    @Test func missRoutesToManualEntryWithBarcode() async {
        let flow = makeFlow(FakeLookup())
        flow.process(barcode: barcode)
        #expect(await waitUntil { flow.sheet != nil })
        guard case .manualEntry(let scanned) = flow.sheet else {
            Issue.record("Expected the manual entry sheet")
            return
        }
        #expect(scanned == barcode)
    }

    @Test func clearlyNonScotchIsRejectedWithNoSheet() async {
        let lookup = FakeLookup()
        lookup.outcome = .hit(bourbon)
        let flow = makeFlow(lookup)
        flow.process(barcode: barcode)
        #expect(await waitUntil { flow.phase == .rejected })
        #expect(flow.sheet == nil)

        flow.dismissRejection()
        #expect(flow.phase == .scanning)
    }

    @Test func existingBarcodeJumpsToTheBottleWithoutALookup() {
        let existing = Bottle(name: "Lagavulin 16", distilleryName: "Lagavulin", region: "islay")
        let lookup = FakeLookup()
        let flow = makeFlow(lookup, existing: [barcode: existing])

        flow.process(barcode: barcode)

        guard case .duplicate(let bottle) = flow.sheet else {
            Issue.record("Expected the duplicate sheet")
            return
        }
        #expect(bottle === existing)
        #expect(lookup.calls.isEmpty)
        #expect(flow.phase == .scanning)
    }

    @Test func twelveDigitUPCMatchesTheStoredThirteenDigitForm() {
        let existing = Bottle(name: "Glenfiddich 12")
        let flow = makeFlow(FakeLookup(), existing: ["0088076161863": existing])
        flow.process(barcode: "088076161863")
        guard case .duplicate = flow.sheet else {
            Issue.record("Expected the duplicate sheet")
            return
        }
    }

    @Test func invalidBarcodeNeverStartsALookup() {
        let lookup = FakeLookup()
        let flow = makeFlow(lookup)
        flow.process(barcode: "../../etc")
        flow.process(barcode: "12345")
        #expect(flow.phase == .scanning)
        #expect(lookup.calls.isEmpty)
    }

    @Test func scansAreIgnoredWhileASheetIsOpen() {
        let lookup = FakeLookup()
        let flow = makeFlow(lookup)
        flow.presentManualForm()
        flow.process(barcode: barcode)
        #expect(lookup.calls.isEmpty)
    }

    @Test func secondScanIsIgnoredWhileLookingUp() async {
        let lookup = FakeLookup()
        lookup.delay = .milliseconds(200)
        let flow = makeFlow(lookup)
        flow.process(barcode: barcode)
        flow.process(barcode: "5010314302409")
        #expect(await waitUntil { flow.sheet != nil })
        #expect(lookup.calls == [barcode])
    }

    @Test func cancelAbandonsTheLookupAndDiscardsItsResult() async throws {
        let lookup = FakeLookup()
        lookup.outcome = .hit(scotch)
        lookup.delay = .milliseconds(150)
        let flow = makeFlow(lookup)

        flow.process(barcode: barcode)
        flow.cancelLookup()
        #expect(flow.phase == .scanning)

        // The abandoned lookup finishing later must not pop a sheet.
        try await Task.sleep(for: .milliseconds(300))
        #expect(flow.sheet == nil)
        #expect(flow.phase == .scanning)
    }

    @Test func cancelledBarcodeIsNotRescannedImmediately() {
        let lookup = FakeLookup()
        lookup.delay = .seconds(5)
        let flow = makeFlow(lookup)
        let start = Date.now

        flow.process(barcode: barcode, now: start)
        flow.cancelLookup(now: start)

        // The code is still in front of the camera a moment later.
        flow.process(barcode: barcode, now: start.addingTimeInterval(1))
        #expect(flow.phase == .scanning)
        #expect(lookup.calls.count == 1)

        // A different bottle is fine straight away.
        flow.process(barcode: "5010314302409", now: start.addingTimeInterval(1))
        #expect(flow.phase == .lookingUp)
        flow.cancelLookup()
    }

    @Test func cancelledBarcodeCanBeScannedAgainAfterTheWindow() {
        let lookup = FakeLookup()
        lookup.delay = .seconds(5)
        let flow = makeFlow(lookup)
        let start = Date.now

        flow.process(barcode: barcode, now: start)
        flow.cancelLookup(now: start)
        flow.process(barcode: barcode, now: start.addingTimeInterval(ScanFlow.cancelSuppression + 1))
        #expect(flow.phase == .lookingUp)
        flow.cancelLookup()
    }

    @Test func retakeClearsTheSheetAndLiveReading() {
        let flow = makeFlow(FakeLookup())
        flow.labelReader.update(lines: ["Lagavulin"])
        flow.sheet = .labelScanResult(LabelScanResult(), photoData: nil)
        flow.retakeLabel()
        #expect(flow.sheet == nil)
        #expect(flow.labelReader.lines.isEmpty)
        #expect(flow.labelReader.result == nil)
    }
}
