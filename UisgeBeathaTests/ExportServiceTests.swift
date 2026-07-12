import Foundation
import Testing
@testable import UisgeBeatha

/// Phase 6 acceptance: exported JSON re-parses with full fidelity
/// (including the invisible country/currencyCode fields) and the CSV is
/// well-formed with notes concatenated.
struct ExportServiceTests {
    private func makeBottle() -> Bottle {
        let bottle = Bottle(
            name: "Lagavulin 16",
            distilleryName: "Lagavulin",
            region: "islay",
            barcode: "5000281005416",
            abv: 43.0,
            ageStatement: 16,
            caskType: "Ex-bourbon, sherry",
            purchasePrice: 89.99,
            status: .open,
            rating: 4.5,
            stockPhotoURL: "https://example.org/l.jpg"
        )
        let older = TastingNote(
            date: Date(timeIntervalSince1970: 1_600_000_000),
            nose: "Peat", palate: "Smoke", finish: "Long", conclusion: "Classic"
        )
        let newer = TastingNote(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            nose: "Iodine", palate: "Sherry", finish: "Ash", conclusion: "Better"
        )
        bottle.notes = [older, newer]
        return bottle
    }

    @Test func jsonRoundTripsWithFullFidelity() throws {
        let data = try ExportService.jsonData(from: [makeBottle()])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ExportService.BottleExport].self, from: data)

        let record = try #require(decoded.first)
        #expect(record.name == "Lagavulin 16")
        #expect(record.region == "islay")
        #expect(record.country == "Scotland", "Invisible fields must be present in exports")
        #expect(record.currencyCode == "USD")
        #expect(record.abv == 43.0)
        #expect(record.ageStatement == 16)
        #expect(record.status == "open")
        #expect(record.rating == 4.5)
        #expect(record.notes.count == 2)
        #expect(record.notes.first?.nose == "Iodine", "Notes export newest first")
    }

    @Test func csvHasHeaderAndOneRowPerBottle() {
        let csv = ExportService.csv(from: [makeBottle()])
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("name,distillery,region,country"))
        #expect(lines[1].contains("Lagavulin 16"))
        #expect(lines[1].contains("Scotland"))
    }

    @Test func csvEscapesCommasAndQuotes() {
        #expect(ExportService.escapeCSVField("Ex-bourbon, sherry") == "\"Ex-bourbon, sherry\"")
        #expect(ExportService.escapeCSVField("The \"Beast\"") == "\"The \"\"Beast\"\"\"")
        #expect(ExportService.escapeCSVField("plain") == "plain")
    }

    @Test func csvConcatenatesNotesIntoOneField() {
        let csv = ExportService.csv(from: [makeBottle()])
        let dataLine = csv.split(separator: "\r\n")[1]
        #expect(dataLine.contains("Nose: Iodine"))
        #expect(dataLine.contains("Nose: Peat"))
        #expect(dataLine.contains(" | "), "Multiple notes joined in one field")
    }

    @Test func emptyCollectionStillProducesValidExports() throws {
        let data = try ExportService.jsonData(from: [])
        #expect(String(decoding: data, as: UTF8.self).contains("[")) // valid empty array
        let csv = ExportService.csv(from: [])
        #expect(csv.hasPrefix("name,"))
    }
}
