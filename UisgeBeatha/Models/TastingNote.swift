import Foundation
import SwiftData

/// A dated tasting note. One bottle can accumulate many over time.
///
/// CloudKit-forward: all attributes defaulted, the back-reference to the
/// bottle is optional. The inverse is declared on `Bottle.notes`.
@Model
final class TastingNote {
    var id: UUID = UUID()
    var date: Date = Date.now
    var nose: String = ""
    var palate: String = ""
    var finish: String = ""
    var conclusion: String = ""

    var bottle: Bottle?

    init(
        date: Date = .now,
        nose: String = "",
        palate: String = "",
        finish: String = "",
        conclusion: String = ""
    ) {
        self.date = date
        self.nose = nose
        self.palate = palate
        self.finish = finish
        self.conclusion = conclusion
    }
}
