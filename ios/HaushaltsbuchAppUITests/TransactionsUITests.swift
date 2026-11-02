import XCTest

/// Live-Prüfung von Buchungsliste und Bearbeiten (setzt eine gespeicherte Sitzung voraus, z. B. nach
/// `OnboardingUITests`; nicht Teil von `scripts/test.sh`). Umgebung: `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`.
final class TransactionsUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    func testEditAndDeleteBooking() throws {
        let app = XCUIApplication()
        app.launch()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        try requireExistence(opener, timeout: 15, "keine gespeicherte Sitzung – vorher anmelden")
        waitUntilHittable(opener)

        // Zwei Ausgaben und eine Einnahme anlegen.
        addBooking(app, opener: opener, keys: [1, 2, 5, 0], category: "Lebensmittel", income: false)
        addBooking(app, opener: opener, keys: [8, 9, 0], category: "Wohnen", income: false)
        addBooking(app, opener: opener, keys: [2, 5, 0, 0, 0, 0], category: "Gehalt", income: true)
        Thread.sleep(forTimeInterval: 4) // Sync (2-s-Debounce)

        openTransactions(app)
        let list = app.collectionViews["transactions.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "Liste fehlt")
        let income = row(app, containing: "2.500,00")
        XCTAssertTrue(income.waitForExistence(timeout: 10), "Einnahme fehlt")
        XCTAssertTrue(income.label.contains("+"), "Einnahme ohne Plus: \(income.label)")
        let target = row(app, containing: "12,50")
        XCTAssertTrue(target.exists, "Ausgabe 12,50 fehlt")
        shot("1-list")

        // Suche
        let search = app.searchFields["Suchen"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Suchfeld fehlt")
        search.tap()
        search.typeText("wohn")
        XCTAssertTrue(row(app, containing: "8,90").waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, containing: "12,50").exists, "Suche filtert nicht")
        shot("2-search")
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["Keine Treffer"].waitForExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
        XCTAssertTrue(row(app, containing: "12,50").waitForExistence(timeout: 5))

        // Bearbeiten: 12,50 -> 4,20
        row(app, containing: "12,50").tap()
        let amount = app.staticTexts["edit.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Bearbeiten-Formular fehlt")
        XCTAssertTrue(amount.label.contains("12,50"), "nicht vorbelegt: \(amount.label)")
        shot("3-edit")
        for _ in 0..<4 { app.buttons["quickEntry.key.delete"].tap() }
        for digit in [4, 2, 0] { app.buttons["quickEntry.key.\(digit)"].tap() }
        XCTAssertTrue(amount.label.contains("4,20"), "Betrag falsch: \(amount.label)")
        app.buttons["edit.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Formular schließt nicht")
        XCTAssertTrue(row(app, containing: "4,20").waitForExistence(timeout: 5), "Betrag nicht aktualisiert")
        XCTAssertFalse(row(app, containing: "12,50").exists)
        Thread.sleep(forTimeInterval: 5) // Sync der Änderung

        // Swipe-Löschen
        let edited = row(app, containing: "4,20")
        edited.swipeLeft()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Löschen-Aktion fehlt")
        delete.tap()
        XCTAssertTrue(edited.waitForNonExistence(timeout: 5), "Zeile bleibt stehen")

        // Pull-to-Refresh
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(row(app, containing: "4,20").exists)
        XCTAssertTrue(row(app, containing: "2.500,00").exists)
        shot("4-after")
    }

    @MainActor
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'transactions.row' AND label CONTAINS %@", text))
            .firstMatch
    }

    @MainActor
    private func openTransactions(_ app: XCUIApplication) {
        if isPad {
            app.collectionViews.staticTexts["Buchungen"].tap()
        } else {
            let tab = app.tabBars.buttons["Buchungen"]
            waitUntilHittable(tab)
            tab.tap()
        }
        XCTAssertTrue(app.navigationBars["Buchungen"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func addBooking(_ app: XCUIApplication, opener: XCUIElement, keys: [Int], category: String, income: Bool) {
        waitUntilHittable(opener)
        opener.tap()
        let amount = app.staticTexts["quickEntry.amount"]
        if !amount.waitForExistence(timeout: 3) { opener.tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Betragsanzeige fehlt")
        for digit in keys { app.buttons["quickEntry.key.\(digit)"].tap() }
        if income {
            let details = app.buttons["Details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 3))
            details.tap()
            let kind = app.buttons["Einnahme"]
            XCTAssertTrue(kind.waitForExistence(timeout: 3))
            kind.tap()
        }
        let cat = app.buttons["quickEntry.category.\(category)"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "Kategorie \(category) fehlt")
        waitUntilHittable(cat)
        cat.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Sheet schließt nicht")
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
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("task-11-\(prefix)-\(name).png"))
    }
}
