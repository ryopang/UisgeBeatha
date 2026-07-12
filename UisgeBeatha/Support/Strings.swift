import Foundation

/// Every user-facing string lives here (PRD section 10.1). Not localization,
/// just one place — and where the Whisky/Whiskey spelling rule is enforced.
/// Always "Whisky", never "Whiskey"; avoid plural forms.
enum Strings {
    enum App {
        static let name = "Uisge Beatha"
    }

    enum Policy {
        static let rejection = "This one isn't a Scotch whisky. Uisge Beatha tracks Scotch only for now."
    }

    enum Status {
        static let sealed = "Sealed"
        static let open = "Open"
        static let finished = "Finished"

        static func label(for status: BottleStatus) -> String {
            switch status {
            case .sealed: sealed
            case .open: open
            case .finished: finished
            }
        }
    }
}
