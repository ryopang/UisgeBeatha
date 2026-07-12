import Foundation

/// Every user-facing string lives here (PRD section 10.1). Not localization,
/// just one place — and where the Whisky/Whiskey spelling rule is enforced.
/// Always "Whisky", never "Whiskey"; avoid plural forms.
/// nonisolated: plain constants, callable from any concurrency context.
nonisolated enum Strings {
    enum App {
        static let name = "Uisge Beatha"
    }

    enum Tabs {
        static let collection = "Collection"
        static let scan = "Scan"
        static let settings = "Settings"
    }

    enum Scan {
        static let title = "Scan"
        static let lookingUp = "Looking up…"
        static let scanAgain = "Scan Again"
        static let cameraUnavailable = "Scanning needs a camera. Enter the barcode digits instead."
        static let barcodeField = "Barcode"
        static let lookUp = "Look Up"
        static let resultTitle = "Match Found"
        static let addToCollection = "Add to Collection"
        static let detailsOnly = "Details Only"
        static let detailsName = "Product"
        static let detailsBrand = "Brand"
        static let detailsCategories = "Categories"
        static let duplicateToast = "Already in your collection."
        static let missNotice = "Not found in the database. Add it manually and it's saved for good."
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
        static let emptyAction = "Scan Your First Bottle"
        static let emptyManualAction = "Add Manually"
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

    enum Map {
        static let listMode = "List"
        static let mapMode = "Map"
        static let viewToggle = "View"
        static let emptyRegionTitle = "Nothing Here Yet"

        static func emptyRegionMessage(region: String) -> String {
            "No \(region) bottle in the collection yet."
        }

        static func badgeLabel(region: String, count: Int) -> String {
            count == 1 ? "\(region), 1 bottle" : "\(region), \(count) bottles"
        }
    }

    enum Detail {
        static let more = "More"
        static let edit = "Edit"
        static let delete = "Delete"
        static let takePhoto = "Take Photo"
        static let choosePhoto = "Choose Photo"
        static let distillery = "Distillery"
        static let region = "Region"
        static let abv = "ABV"
        static let age = "Age"
        static let nas = "NAS"
        static let caskType = "Cask Type"
        static let status = "Status"
        static let statusHint = "Cycles between sealed, open, and finished"
        static let price = "Price"
        static let purchased = "Purchased"
        static let added = "Added"
        static let ratingSection = "Rating"
        static let notesSection = "Tasting Notes"
        static let newNote = "New Tasting Note"
        static let noNotes = "No tasting notes yet. Pour a dram and write the first one."
        static let noteActions = "Note actions"
        static let deleteNoteTitle = "Delete Note?"

        static func ageValue(_ years: Int) -> String {
            years == 1 ? "1 Year" : "\(years) Years"
        }
    }

    enum NoteEditor {
        static let title = "Tasting Note"
        static let date = "Date"
        static let nose = "Nose"
        static let palate = "Palate"
        static let finish = "Finish"
        static let conclusion = "Conclusion"
        static let wheelButton = "Flavour Wheel"
    }

    enum Wheel {
        static let title = "Flavour Wheel"
        static let done = "Done"
        static let caption = "A reference for finding the words: categories on the inner ring, descriptors on the outer."
        static let accessibilitySummary = "Whisky flavour wheel with eight categories: Smoky, Fruity, Floral, Malty, Woody, Spicy, Sweet, and Maritime."

        static let smoky = "Smoky"
        static let smokyDescriptors = ["Peat", "Bonfire", "Medicinal"]
        static let fruity = "Fruity"
        static let fruityDescriptors = ["Orchard", "Citrus", "Dried Fruit"]
        static let floral = "Floral"
        static let floralDescriptors = ["Heather", "Blossom", "Grassy"]
        static let malty = "Malty"
        static let maltyDescriptors = ["Biscuit", "Cereal", "Toast"]
        static let woody = "Woody"
        static let woodyDescriptors = ["Oak", "Vanilla", "Resin"]
        static let spicy = "Spicy"
        static let spicyDescriptors = ["Pepper", "Cinnamon", "Ginger"]
        static let sweet = "Sweet"
        static let sweetDescriptors = ["Honey", "Caramel", "Sherry"]
        static let maritime = "Maritime"
        static let maritimeDescriptors = ["Brine", "Seaweed", "Salt"]
    }

    enum Settings {
        static let title = "Settings"
        static let aboutSection = "About"
        static let version = "Version"
        static let dataNotice = "Your collection stays on this device. Nothing is uploaded anywhere."
        static let debugSection = "Debug"
        static let lastLookupSource = "Last Lookup Source"
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
