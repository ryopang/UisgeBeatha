import XCTest

/// Phase 6 drive: distillery card on the detail (stubbed Wikipedia),
/// seed facts, and export share links in Settings.
final class PolishFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDistilleryCardAndExportLinks() throws {
        let app = XCUIApplication()
        // The simulator has no iCloud account; keep the store local.
        app.launchArguments += ["-disableCloudSync"]
        app.launchArguments += ["-uiTestLookupStub"]
        app.launch()

        // Ensure at least one bottle exists (fresh-install friendly).
        addBottleIfMissing(app, name: "Oban 14", distilleryPrefix: "Oba", region: "Highland")

        // Distillery card: Wikipedia extract (stub) + seed facts.
        app.staticTexts["Oban 14"].firstMatch.tap()
        let cardExtract = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'stub distillery summary'")
        ).firstMatch
        var swipes = 0
        while !cardExtract.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(cardExtract.exists, "Distillery card should show the Wikipedia extract")
        XCTAssertTrue(
            app.staticTexts["1794"].exists || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS '1794'")
            ).firstMatch.exists,
            "Seed facts (founded year) should show on the card"
        )
        XCTAssertTrue(app.buttons["Read more on Wikipedia"].exists)

        // Export links in Settings.
        app.buttons["Settings"].tap()
        XCTAssertTrue(
            app.buttons["Export Collection as JSON"].waitForExistence(timeout: 5),
            "JSON export ShareLink should be available"
        )
        XCTAssertTrue(app.buttons["Export Collection as CSV"].exists)
        XCTAssertTrue(
            app.staticTexts["Photos are not included in exports."].exists,
            "The photos note should be visible"
        )

        // Opening the share sheet works; dismissal is best-effort since the
        // system sheet's close control varies by OS version.
        app.buttons["Export Collection as JSON"].tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 8), "Share sheet should present the export")
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() }
    }

    private func addBottleIfMissing(
        _ app: XCUIApplication, name: String, distilleryPrefix: String, region: String
    ) {
        let listButton = app.buttons["List"]
        if listButton.waitForExistence(timeout: 10) {
            listButton.tap()
        }
        if app.staticTexts[name].firstMatch.waitForExistence(timeout: 3) { return }

        let toolbarAdd = app.buttons["Add Bottle"]
        let emptyAdd = app.buttons["Add Manually"]
        if toolbarAdd.waitForExistence(timeout: 5) {
            toolbarAdd.tap()
        } else {
            XCTAssertTrue(emptyAdd.waitForExistence(timeout: 5))
            emptyAdd.tap()
        }
        let nameField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        let distilleryField = app.textFields.element(boundBy: 1)
        distilleryField.tap()
        distilleryField.typeText(distilleryPrefix)
        let suggestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", distilleryPrefix, region)
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
    }
}
