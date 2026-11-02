import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 1: live label parsing is throttled and off the main actor.
@MainActor
struct LiveLabelReaderTests {
    private let distilleries = DistilleryStore(distilleries: [
        Distillery(
            name: "Lagavulin", aliases: [], region: "islay",
            lat: 55.6365, lon: -6.1268, founded: 1816, owner: "Diageo",
            wikipediaTitle: "Lagavulin_distillery"
        ),
    ])

    private func makeReader(interval: Duration = .milliseconds(20)) -> LiveLabelReader {
        LiveLabelReader(
            distilleryStore: distilleries,
            expressionStore: ExpressionStore(expressions: []),
            interval: interval
        )
    }

    @Test func parsesLinesIntoAResult() async {
        let reader = makeReader()
        reader.update(lines: ["LAGAVULIN", "16 Year Old", "43% Vol"])
        #expect(await waitUntil { reader.result != nil })
        #expect(reader.result?.distilleryName == "Lagavulin")
        #expect(reader.result?.age == 16)
    }

    @Test func burstOfUpdatesEndsWithTheNewestLines() async {
        let reader = makeReader()
        reader.update(lines: ["Nothing useful here"])
        reader.update(lines: ["LAGAVULIN"])
        reader.update(lines: ["LAGAVULIN", "12 Year Old"])
        #expect(await waitUntil { reader.result?.age == 12 })
        #expect(reader.result?.distilleryName == "Lagavulin")
    }

    @Test func resetClearsLinesAndResultAndDropsAPendingParse() async throws {
        let reader = makeReader(interval: .milliseconds(100))
        reader.update(lines: ["LAGAVULIN"])
        reader.reset()
        #expect(reader.lines.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        #expect(reader.result == nil, "A parse scheduled before reset must not resurrect the result")
    }

    @Test func emptyLinesProduceNoResult() async {
        let reader = makeReader()
        reader.update(lines: ["LAGAVULIN"])
        #expect(await waitUntil { reader.result != nil })
        reader.update(lines: [])
        #expect(await waitUntil { reader.result == nil })
    }
}
