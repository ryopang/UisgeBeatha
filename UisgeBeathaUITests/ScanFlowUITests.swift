import XCTest

/// Phase 4 drive with the stubbed lookup service (-uiTestLookupStub):
/// hit → result sheet → prefilled form → saved; duplicate → jump to
/// detail; non-scotch → rejection with no add path; miss → manual form
/// with barcode prefilled. The live camera path needs a device.
final class ScanFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testScanHitDuplicateRejectionAndMissPaths() throws {
        let app = XCUIApplication()
        // The simulator has no iCloud account; keep the store local.
        app.launchArguments += ["-disableCloudSync"]
        app.launchArguments += ["-uiTestLookupStub"]
        app.launch()

        // The simulator has no camera, so the scan tab offers manual entry.
        app.buttons["Scan"].tap()
        let barcodeField = app.textFields["Barcode"]
        XCTAssertTrue(barcodeField.waitForExistence(timeout: 10), "Manual entry fallback should show")

        // Hit path: result sheet with matched distillery and region.
        lookUp(app, barcode: "1111111111111")
        XCTAssertTrue(
            app.staticTexts["Lagavulin 16 Year Old Islay Single Malt"].waitForExistence(timeout: 10),
            "Result sheet should show the product"
        )
        XCTAssertTrue(app.staticTexts["Islay"].exists, "Matched region tag should show")

        // Add to Collection opens the form pre-filled for confirmation.
        app.buttons["Add to Collection"].tap()
        let nameField = app.textFields.matching(
            NSPredicate(format: "value CONTAINS 'Lagavulin 16'")
        ).firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Name should be pre-filled from the lookup")
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.isEnabled, "Prefill should satisfy validation")
        saveButton.tap()

        // The whole sheet chain dismisses back to the scanner.
        XCTAssertTrue(barcodeField.waitForExistence(timeout: 5), "Should land back on the scan tab")

        // The bottle landed in the collection.
        app.buttons["Collection"].tap()
        XCTAssertTrue(
            app.staticTexts["Lagavulin 16 Year Old Islay Single Malt"].firstMatch.waitForExistence(timeout: 5)
        )

        // Duplicate: rescanning the same barcode jumps to the bottle detail.
        app.buttons["Scan"].tap()
        lookUp(app, barcode: "1111111111111")
        XCTAssertTrue(
            app.staticTexts["Already in your collection."].waitForExistence(timeout: 10),
            "Duplicate scan should show the toast"
        )
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Status'"))
                .firstMatch.waitForExistence(timeout: 5),
            "Duplicate scan should land on the bottle detail"
        )
        app.swipeDown(velocity: .fast) // dismiss the duplicate sheet

        // Scotch gate: bourbon is politely rejected with no add path.
        lookUp(app, barcode: "2222222222222")
        XCTAssertTrue(
            app.staticTexts["This one isn't a Scotch whisky. Uisge Beatha tracks Scotch only for now."]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.buttons["Add to Collection"].exists, "Rejection must offer no add path")
        app.buttons["Scan Again"].tap()

        // Miss path: manual form with the barcode pre-filled and the notice.
        lookUp(app, barcode: "9999999999999")
        XCTAssertTrue(
            app.staticTexts["Not found in the database. Add it manually and it's saved for good."]
                .waitForExistence(timeout: 10),
            "Miss should route to the manual form with the notice"
        )
        let barcodeValue = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '9999999999999' OR value CONTAINS '9999999999999'")
        ).firstMatch
        var swipes = 0
        while !barcodeValue.exists && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(barcodeValue.exists, "Barcode should be pre-filled read-only")
        app.buttons["Cancel"].tap()
    }

    private func lookUp(_ app: XCUIApplication, barcode: String) {
        let field = app.textFields["Barcode"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(barcode)
        app.buttons["Look Up"].tap()
    }
}
