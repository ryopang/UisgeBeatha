import XCTest

/// End-to-end drive of the Phase 2 flow: empty state → add via form with
/// distillery autocomplete → search → status cycle → delete → persistence
/// across relaunch. Run against a freshly installed app for the empty state.
final class CollectionFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddSearchCycleDeleteAndPersistence() throws {
        let app = XCUIApplication()
        app.launch()

        // Empty state on fresh install: scan is primary, manual add secondary.
        let scanActionButton = app.buttons["Scan Your First Bottle"]
        XCTAssertTrue(scanActionButton.waitForExistence(timeout: 10), "Empty state should show on fresh install")
        app.buttons["Add Manually"].tap()

        // Save must be disabled until required fields are filled.
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled while the form is empty")

        // Fill name and distillery; picking the autocomplete suggestion
        // must auto-fill the region.
        let nameField = app.textFields.element(boundBy: 0)
        nameField.tap()
        nameField.typeText("Lagavulin 16")

        let distilleryField = app.textFields.element(boundBy: 1)
        distilleryField.tap()
        distilleryField.typeText("Lagavu")

        let suggestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Lagavulin' AND label CONTAINS 'Islay'")
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "Autocomplete suggestion should appear")
        suggestion.tap()

        XCTAssertTrue(
            waitForValue(of: distilleryField, toContain: "Lagavulin", timeout: 5),
            "Tapping the suggestion should fill the distillery field; value is \(String(describing: distilleryField.value))"
        )
        XCTAssertTrue(
            app.staticTexts["Islay"].waitForExistence(timeout: 5),
            "Region should be auto-filled from the distillery match"
        )
        XCTAssertTrue(
            waitForEnabled(saveButton, timeout: 5),
            "Save should enable once name, distillery, and region are set"
        )
        saveButton.tap()

        let lagavulinRow = app.staticTexts["Lagavulin 16"]
        XCTAssertTrue(lagavulinRow.waitForExistence(timeout: 5), "Saved bottle should appear in the list")

        // Second bottle via the toolbar add button.
        app.buttons["Add Bottle"].tap()
        let secondName = app.textFields.element(boundBy: 0)
        XCTAssertTrue(secondName.waitForExistence(timeout: 5))
        secondName.tap()
        secondName.typeText("Ardbeg 10")
        let secondDistillery = app.textFields.element(boundBy: 1)
        secondDistillery.tap()
        secondDistillery.typeText("Ardbe")
        let ardbegSuggestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Ardbeg' AND label CONTAINS 'Islay'")
        ).firstMatch
        XCTAssertTrue(ardbegSuggestion.waitForExistence(timeout: 5))
        ardbegSuggestion.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Ardbeg 10"].waitForExistence(timeout: 5))

        // Search filters on name.
        app.swipeDown()
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field should be revealed")
        searchField.tap()
        searchField.typeText("lagavulin")
        XCTAssertTrue(lagavulinRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ardbeg 10"].exists, "Search should filter out non-matching bottles")
        // Search matching nothing shows an empty result, not an error.
        searchField.typeText("zzz")
        XCTAssertFalse(lagavulinRow.exists)

        // Leave search so the full list returns.
        let clearTextButton = searchField.buttons["Clear text"]
        if clearTextButton.exists { clearTextButton.tap() }
        let cancelSearch = app.buttons["Cancel"]
        if cancelSearch.waitForExistence(timeout: 3) {
            cancelSearch.tap()
        }

        // Leading swipe sets status. A new bottle starts with *no* status
        // (BottleStatus.next(after: nil)), so the first cycle lands on
        // Sealed rather than advancing from a presumed Sealed to Open.
        let lagavulinCell = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Lagavulin 16'")
        ).firstMatch
        XCTAssertTrue(lagavulinCell.waitForExistence(timeout: 5), "Full list should return after leaving search")
        lagavulinCell.swipeRight()
        let statusAction = app.buttons["Status"]
        XCTAssertTrue(statusAction.waitForExistence(timeout: 5))
        statusAction.tap()

        // The row deliberately doesn't render status text (BottleRowView
        // keeps rows uncluttered at accessibility Dynamic Type sizes), so
        // confirm the change landed on the detail screen instead.
        lagavulinRow.tap()
        let statusButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Status'")
        ).firstMatch
        XCTAssertTrue(statusButton.waitForExistence(timeout: 5), "Detail should show the status control")
        XCTAssertTrue(
            statusButton.label.contains("Sealed"),
            "First status cycle from unset should land on Sealed; got \(statusButton.label)"
        )
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(lagavulinCell.waitForExistence(timeout: 5), "Should return to the list")

        // Trailing swipe deletes after confirmation.
        lagavulinCell.swipeLeft()
        let deleteAction = app.buttons["Delete"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()
        XCTAssertTrue(
            app.staticTexts["Delete Bottle?"].waitForExistence(timeout: 5),
            "Delete should ask for confirmation"
        )
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(
            waitForDisappearance(of: lagavulinRow, timeout: 5),
            "Deleted bottle should leave the list"
        )
        XCTAssertTrue(app.staticTexts["Ardbeg 10"].exists, "Other bottles should survive a delete")

        // Data persists across relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Ardbeg 10"].waitForExistence(timeout: 10),
            "Collection should persist across relaunch"
        )
        XCTAssertFalse(app.staticTexts["Lagavulin 16"].exists, "Deleted bottle should stay deleted")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(of element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

}
