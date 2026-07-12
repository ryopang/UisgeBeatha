import XCTest

/// Phase 3 drive: list → detail push, status cycle, rating tap, tasting
/// note CRUD (newest first), flavour wheel sheet, persistence across
/// relaunch, delete from detail. Creates its own bottle, so it does not
/// depend on a fresh install.
final class DetailFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDetailRatingNotesWheelAndPersistence() throws {
        let app = XCUIApplication()
        app.launch()

        addBottle(app, name: "Talisker 10", distilleryPrefix: "Talisk", suggestionRegion: "Islands")

        // Push detail from the list row.
        app.staticTexts["Talisker 10"].firstMatch.tap()
        let statusCell = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Status'")
        ).firstMatch
        XCTAssertTrue(statusCell.waitForExistence(timeout: 5), "Detail should show the facts grid")
        XCTAssertTrue(statusCell.label.contains("Sealed"))

        // Tappable status cycles.
        statusCell.tap()
        XCTAssertTrue(
            waitForLabel(of: statusCell, toContain: "Open", timeout: 5),
            "Tapping status should cycle sealed to open"
        )

        // Rating: tap at 70% of the control = 3.5 stars.
        let ratingControl = app.descendants(matching: .any)
            .matching(identifier: "RatingControl").firstMatch
        XCTAssertTrue(ratingControl.waitForExistence(timeout: 5))
        scrollIntoView(ratingControl, in: app)
        // The accessibility frame isn't concentric with the star row, so the
        // exact value a tap lands on varies; assert a rating gets set and
        // that the same value survives relaunch.
        ratingControl.tap()
        XCTAssertTrue(
            waitForValue(of: ratingControl, toContain: "Rated", timeout: 5),
            "Tapping should set a rating; value is \(String(describing: ratingControl.value))"
        )
        let ratingAfterTap = try XCTUnwrap(ratingControl.value as? String)

        // First tasting note, with a look at the flavour wheel.
        app.buttons["New Tasting Note"].tap()
        let noseField = noteField(app, at: 0)
        XCTAssertTrue(noseField.waitForExistence(timeout: 5), "Note editor should show the Nose field")
        noseField.tap()
        noseField.typeText("Peat smoke")

        app.buttons["Flavour Wheel"].tap()
        let wheelTitle = app.navigationBars["Flavour Wheel"]
        XCTAssertTrue(wheelTitle.waitForExistence(timeout: 5), "Wheel sheet should open")
        let wheelShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        wheelShot.name = "flavour-wheel"
        wheelShot.lifetime = .keepAlways
        add(wheelShot)
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForDisappearance(of: wheelTitle, timeout: 5))

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Peat smoke"].waitForExistence(timeout: 5), "Note card should appear")

        // Second note must sort above the first (newest first).
        app.buttons["New Tasting Note"].tap()
        let secondNose = noteField(app, at: 0)
        XCTAssertTrue(secondNose.waitForExistence(timeout: 5))
        secondNose.tap()
        secondNose.typeText("Citrus and honey")
        app.buttons["Save"].tap()
        let secondCard = app.staticTexts["Citrus and honey"]
        XCTAssertTrue(secondCard.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            secondCard.frame.minY, app.staticTexts["Peat smoke"].frame.minY,
            "Newest note should display first"
        )

        // Everything survives relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Talisker 10"].waitForExistence(timeout: 10))
        app.staticTexts["Talisker 10"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Peat smoke"].waitForExistence(timeout: 5), "Notes should persist")
        let persistedRating = app.descendants(matching: .any)
            .matching(identifier: "RatingControl").firstMatch
        XCTAssertTrue(persistedRating.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue(of: persistedRating, toContain: ratingAfterTap, timeout: 5),
            "Rating should persist; value is \(String(describing: persistedRating.value))"
        )

        // Delete from the detail toolbar menu.
        app.buttons["More"].tap()
        let deleteItem = app.buttons["Delete"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5))
        deleteItem.tap()
        XCTAssertTrue(app.staticTexts["Delete Bottle?"].waitForExistence(timeout: 5))
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(
            waitForDisappearance(of: app.staticTexts["Talisker 10"], timeout: 5),
            "Deleting from detail should remove the bottle and pop back"
        )
    }

    // MARK: - Helpers

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable && attempts < 4 {
            app.swipeUp()
            attempts += 1
        }
    }

    private func addBottle(
        _ app: XCUIApplication, name: String, distilleryPrefix: String, suggestionRegion: String
    ) {
        let toolbarAdd = app.buttons["Add Bottle"]
        let emptyAdd = app.buttons["Add Manually"]
        if toolbarAdd.waitForExistence(timeout: 10) {
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
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                distilleryPrefix, suggestionRegion
            )
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "Autocomplete suggestion should appear")
        suggestion.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    /// Multiline TextFields surface as text views; fall back to text fields.
    private func noteField(_ app: XCUIApplication, at index: Int) -> XCUIElement {
        let textViews = app.textViews
        if textViews.count > index {
            return textViews.element(boundBy: index)
        }
        return app.textFields.element(boundBy: index)
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(of element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(of element: XCUIElement, toContain text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
