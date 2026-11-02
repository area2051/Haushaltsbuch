import XCTest

/// Live-Prüfung der Schnellerfassung (setzt eine gespeicherte Sitzung voraus, z. B. nach
/// `OnboardingUITests`; nicht Teil von `scripts/test.sh`). Umgebung wie dort:
/// `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`.
final class QuickEntryUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor
    func testQuickEntrySavesBooking() throws {
        let app = XCUIApplication()
        app.launch()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        guard opener.waitForExistence(timeout: 15) else { throw XCTSkip("keine gespeicherte Sitzung") }
        waitUntilHittable(opener)
        opener.tap()
        let amount = app.staticTexts["quickEntry.amount"]
        if !amount.waitForExistence(timeout: 3) { opener.tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Betragsanzeige fehlt")
        XCTAssertTrue(amount.label.contains("0,00"), "Anzeige nicht leer: \(amount.label)")
        shot("1-empty")

        for digit in [1, 2, 5, 0] {
            app.buttons["quickEntry.key.\(digit)"].tap()
        }
        XCTAssertTrue(amount.label.contains("12,50"), "Betrag falsch: \(amount.label)")
        shot("2-amount")

        // Details einmal aufklappen (Screenshot), dann wieder zu.
        let details = app.buttons["Details"].firstMatch
        if details.waitForExistence(timeout: 2) {
            details.tap()
            XCTAssertTrue(app.buttons["Einnahme"].waitForExistence(timeout: 3), "Details nicht aufgeklappt")
            shot("3-details")
            details.tap()
        }

        let category = app.buttons["quickEntry.category.Lebensmittel"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), "Kategorie Lebensmittel fehlt")
        waitUntilHittable(category)
        category.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Sheet schließt nicht")
        // Dem 2-s-Debounce des Syncs Zeit geben, bevor die App beendet wird.
        Thread.sleep(forTimeInterval: 6)
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
    }

    @MainActor
    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["HB_SCREENSHOT_DIR"] else { return }
        let prefix = env["HB_SCREENSHOT_PREFIX"] ?? "device"
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("task-10-\(prefix)-\(name).png"))
    }
}
