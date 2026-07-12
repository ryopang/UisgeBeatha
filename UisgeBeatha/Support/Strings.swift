import Foundation

/// Every user-facing string lives here (PRD section 10.1). Not localization,
/// just one place — and where the Whisky/Whiskey spelling rule is enforced.
/// Always "Whisky", never "Whiskey"; avoid plural forms.
enum Strings {
    enum App {
        static let name = "Uisge Beatha"
    }

    enum Tabs {
        static let collection = "Collection"
        static let settings = "Settings"
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

    enum Collection {
        static let title = "Collection"
        static let searchPrompt = "Search name or distillery"
        static let sort = "Sort"
        static let sortByName = "Name"
        static let sortByDistillery = "Distillery"
        static let sortByRegion = "Region"
        static let addBottle = "Add Bottle"
        static let emptyTitle = "An Empty Shelf"
        static let emptyMessage = "Your collection starts with a single bottle."
        static let emptyAction = "Add Your First Bottle"
        static let deleteConfirmTitle = "Delete Bottle?"
        static let deleteConfirmMessage = "This removes the bottle and its tasting notes."
        static let delete = "Delete"
        static let cancel = "Cancel"
        static let statusSwipeLabel = "Status"
    }

    enum Form {
        static let newTitle = "New Bottle"
        static let editTitle = "Edit Bottle"
        static let bottleSection = "Bottle"
        static let detailSection = "Details"
        static let purchaseSection = "Purchase"
        static let name = "Name"
        static let namePlaceholder = "Lagavulin 16"
        static let distillery = "Distillery"
        static let distilleryPlaceholder = "Start typing to search"
        static let region = "Region"
        static let regionPlaceholder = "Select a region"
        static let abv = "ABV %"
        static let noAgeStatement = "No age statement (NAS)"
        static let age = "Age (years)"
        static let caskType = "Cask type"
        static let caskTypePlaceholder = "Ex-bourbon, PX finish"
        static let price = "Price"
        static let hasPurchaseDate = "Add purchase date"
        static let purchaseDate = "Purchased"
        static let status = "Status"
        static let barcode = "Barcode"
        static let save = "Save"
        static let cancel = "Cancel"
    }

    enum Settings {
        static let title = "Settings"
        static let aboutSection = "About"
        static let version = "Version"
        static let dataNotice = "Your collection stays on this device. Nothing is uploaded anywhere."
    }

    enum Accessibility {
        static func rating(_ value: Double) -> String {
            let whole = Int(value)
            let hasHalf = value - Double(whole) >= 0.5
            let stars = whole == 1 && !hasHalf ? "star" : "stars"
            return hasHalf ? "Rated \(whole) and a half \(stars)" : "Rated \(whole) \(stars)"
        }
        static let unrated = "Not yet rated"
    }
}
