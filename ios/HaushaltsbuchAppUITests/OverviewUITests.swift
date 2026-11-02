import XCTest

/// Live-Prüfung von Übersicht und Budgets (setzt eine gespeicherte Sitzung voraus; nicht Teil von `scripts/test.sh`).
/// `HB_PHASE=seed` legt Buchungen und Budgets an, sonst werden nur Screenshots gemacht.
/// Umgebung: `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`.
final class OverviewUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    func testOverviewAndBudgets() throws {
        let app = XCUIApplication()
        app.launch()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        try requireExistence(opener, timeout: 15, "keine gespeicherte Sitzung – vorher anmelden")

        if env["HB_PHASE"] == "seed" {
            waitUntilHittable(opener)
            add(app, opener, [2, 6, 0, 0, 0], "Lebensmittel", income: false)
            add(app, opener, [8, 0, 0, 0, 0, 0], "Wohnen", income: false)
            add(app, opener, [4, 5, 0, 0], "Mobilität", income: false)
            add(app, opener, [3, 0, 0, 0], "Freizeit", income: false)
            add(app, opener, [2, 5, 0, 0, 0, 0], "Gehalt", income: true)
            Thread.sleep(forTimeInterval: 3)
            open(app, "Budgets")
            setBudget(app, "Lebensmittel", [3, 0, 0, 0, 0])   // 260 von 300 = 86 %
            setBudget(app, "Wohnen", [7, 0, 0, 0, 0])         // 800 von 700 = überschritten
            setBudget(app, "Freizeit", [5, 0, 0, 0, 0])       // 30 von 50 = ok
            Thread.sleep(forTimeInterval: 4)
        }

        open(app, "Übersicht")
        XCTAssertTrue(app.staticTexts["overview.balance"].waitForExistence(timeout: 10))
        shot("1-overview")
        app.swipeUp()
        shot("2-overview-scrolled")
        app.swipeUp()
        shot("2b-overview-bottom")
        // Vorheriger Monat (leer) und zurück
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        app.buttons["overview.prevMonth"].tap()
        XCTAssertTrue(app.otherElements["overview.empty"].waitForExistence(timeout: 5)
                      || app.staticTexts["Noch keine Buchungen in diesem Monat"].exists)
        shot("3-overview-empty")
        app.buttons["overview.nextMonth"].tap()
        XCTAssertFalse(app.buttons["overview.nextMonth"].isEnabled, "Zukunft darf nicht erreichbar sein")
        open(app, "Budgets")
        XCTAssertTrue(app.buttons.matching(identifier: "budgets.row").firstMatch.waitForExistence(timeout: 5))
        shot("4-budgets")
    }

    @MainActor
    private func open(_ app: XCUIApplication, _ name: String) {
        if isPad {
            app.collectionViews.staticTexts[name].tap()
        } else {
            let tab = app.tabBars.buttons[name]
            waitUntilHittable(tab)
            tab.tap()
        }
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    @MainActor
    private func setBudget(_ app: XCUIApplication, _ category: String, _ keys: [Int]) {
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'budgets.row' AND label CONTAINS %@", category)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Zeile \(category) fehlt")
        row.tap()
        let save = app.buttons["budget.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        if app.buttons["budget.remove"].exists { app.buttons["budget.remove"].tap(); return }
        for d in keys { app.buttons["quickEntry.key.\(d)"].tap() }
        shot("budget-edit-\(category)")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func add(_ app: XCUIApplication, _ opener: XCUIElement, _ keys: [Int], _ category: String, income: Bool) {
        waitUntilHittable(opener)
        opener.tap()
        let amount = app.staticTexts["quickEntry.amount"]
        if !amount.waitForExistence(timeout: 3) { opener.tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        for d in keys { app.buttons["quickEntry.key.\(d)"].tap() }
        if income {
            app.buttons["Details"].firstMatch.tap()
            app.buttons["Einnahme"].tap()
        }
        let cat = app.buttons["quickEntry.category.\(category)"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "Kategorie \(category) fehlt")
        waitUntilHittable(cat)
        cat.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "hittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = env["HB_SCREENSHOT_DIR"] else { return }
        let prefix = env["HB_SCREENSHOT_PREFIX"] ?? "device"
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("task-12-\(prefix)-\(name).png"))
    }
}
