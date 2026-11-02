import XCTest

/// Phase 5 drive: List | Map toggle, region badges with counts, dimmed
/// zero-count regions, badge → region sheet → bottle → detail navigation,
/// and toggle persistence across relaunch.
final class MapFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMapBadgesRegionSheetAndTogglePersistence() throws {
        let app = XCUIApplication()
        // The simulator has no iCloud account; keep the store local.
        app.launchArguments += ["-disableCloudSync"]
        app.launch()

        // Seed one Islay bottle so exactly one region has a count.
        addBottleIfMissing(app, name: "Ardbeg Uigeadail", distilleryPrefix: "Ardbe", region: "Islay")

        // Switch to the map.
        app.buttons["Map"].tap()
        let islayBadge = app.buttons["region-badge-islay"]
        XCTAssertTrue(islayBadge.waitForExistence(timeout: 10), "Region badges should render on the map")
        XCTAssertTrue(
            islayBadge.label.range(of: "[1-9][0-9]* bottle", options: .regularExpression) != nil,
            "Islay must show a non-zero count: \(islayBadge.label)"
        )

        // All six regions render; empty ones report zero.
        let campbeltownBadge = app.buttons["region-badge-campbeltown"]
        XCTAssertTrue(campbeltownBadge.waitForExistence(timeout: 5))
        XCTAssertTrue(campbeltownBadge.label.contains("0 bottles"), "Zero-count region: \(campbeltownBadge.label)")

        let mapShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        mapShot.name = "region-map"
        mapShot.lifetime = .keepAlways
        add(mapShot)

        // Badge → sheet listing the region's bottles → bottle detail.
        islayBadge.tap()
        let bottleRow = app.staticTexts["Ardbeg Uigeadail"].firstMatch
        XCTAssertTrue(bottleRow.waitForExistence(timeout: 5), "Region sheet should list its bottles")
        bottleRow.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Status'"))
                .firstMatch.waitForExistence(timeout: 5),
            "Tapping a bottle in the region sheet should push its detail"
        )
        app.swipeDown(velocity: .fast) // dismiss the region sheet

        // The toggle choice persists across relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.buttons["region-badge-islay"].waitForExistence(timeout: 10),
            "Map mode should persist across relaunch"
        )

        // Switch back to list for other tests.
        app.buttons["List"].tap()
        XCTAssertTrue(app.staticTexts["Ardbeg Uigeadail"].firstMatch.waitForExistence(timeout: 5))
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
