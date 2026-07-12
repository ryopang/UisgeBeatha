import Foundation

/// JSON and CSV export (PRD F8). JSON is full fidelity — every field
/// including `country` and `currencyCode` — so exports made today import
/// cleanly into future versions (PRD 10.1). Photos are not included.
enum ExportService {
    // MARK: - JSON

    struct NoteExport: Codable {
        let id: UUID
        let date: Date
        let nose: String
        let palate: String
        let finish: String
        let conclusion: String
    }

    struct BottleExport: Codable {
        let id: UUID
        let name: String
        let distilleryName: String
        let region: String
        let country: String
        let barcode: String?
        let abv: Double?
        let ageStatement: Int?
        let caskType: String?
        let purchasePrice: Decimal?
        let currencyCode: String
        let purchaseDate: Date?
        let status: String
        let rating: Double?
        let stockPhotoURL: String?
        let userPhotoFilename: String?
        let dateAdded: Date
        let notes: [NoteExport]
    }

    static func jsonData(from bottles: [Bottle]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bottles.map { exportRecord(for: $0) })
    }

    static func exportRecord(for bottle: Bottle) -> BottleExport {
        BottleExport(
            id: bottle.id,
            name: bottle.name,
            distilleryName: bottle.distilleryName,
            region: bottle.region,
            country: bottle.country,
            barcode: bottle.barcode,
            abv: bottle.abv,
            ageStatement: bottle.ageStatement,
            caskType: bottle.caskType,
            purchasePrice: bottle.purchasePrice,
            currencyCode: bottle.currencyCode,
            purchaseDate: bottle.purchaseDate,
            status: bottle.status.rawValue,
            rating: bottle.rating,
            stockPhotoURL: bottle.stockPhotoURL,
            userPhotoFilename: bottle.userPhotoFilename,
            dateAdded: bottle.dateAdded,
            notes: sortedNotes(of: bottle).map { note in
                NoteExport(
                    id: note.id, date: note.date, nose: note.nose,
                    palate: note.palate, finish: note.finish, conclusion: note.conclusion
                )
            }
        )
    }

    // MARK: - CSV

    static let csvHeader = "name,distillery,region,country,barcode,abv,age,caskType,"
        + "price,currency,purchaseDate,status,rating,dateAdded,notes"

    /// Flat CSV, one row per bottle, notes concatenated (PRD F8).
    static func csv(from bottles: [Bottle]) -> String {
        var lines = [csvHeader]
        let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        for bottle in bottles {
            let notes = sortedNotes(of: bottle).map { note in
                let parts = [
                    ("Nose", note.nose), ("Palate", note.palate),
                    ("Finish", note.finish), ("Conclusion", note.conclusion),
                ]
                .filter { !$0.1.isEmpty }
                .map { "\($0.0): \($0.1)" }
                .joined(separator: "; ")
                return "\(note.date.formatted(dateFormat)) — \(parts)"
            }
            .joined(separator: " | ")

            var fields: [String] = []
            fields.append(bottle.name)
            fields.append(bottle.distilleryName)
            fields.append(bottle.region)
            fields.append(bottle.country)
            fields.append(bottle.barcode ?? "")
            fields.append(bottle.abv.map { "\($0)" } ?? "")
            fields.append(bottle.ageStatement.map { "\($0)" } ?? "")
            fields.append(bottle.caskType ?? "")
            fields.append(bottle.purchasePrice.map { "\($0)" } ?? "")
            fields.append(bottle.currencyCode)
            fields.append(bottle.purchaseDate.map { $0.formatted(dateFormat) } ?? "")
            fields.append(bottle.status.rawValue)
            fields.append(bottle.rating.map { "\($0)" } ?? "")
            fields.append(bottle.dateAdded.formatted(dateFormat))
            fields.append(notes)
            lines.append(fields.map(escapeCSVField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func sortedNotes(of bottle: Bottle) -> [TastingNote] {
        (bottle.notes ?? []).sorted { $0.date > $1.date }
    }
}
