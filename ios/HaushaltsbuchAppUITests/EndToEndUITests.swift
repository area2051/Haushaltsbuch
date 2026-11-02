import XCTest

/// Bausteine der manuellen Ende-zu-Ende-Prüfung (zwei Simulatoren, ein Server; nicht Teil von
/// `scripts/test.sh`). Die Schritte werden einzeln mit `-only-testing:HaushaltsbuchAppUITests/EndToEndUITests/<test>`
/// auf iPhone und iPad abwechselnd ausgeführt, der Server wird dazwischen per `docker compose stop/start api` gesteuert.
///
/// Umgebung (`TEST_RUNNER_`-Präfix): `HB_PASSWORD` (Passwort des neuen Mitglieds), `HB_MEMBER_USERNAME` (Standard `anna`),
/// `HB_AMOUNT` (Ziffern, z. B. `1111` = 11,11 €), `HB_EDIT_FROM` (Teil des Zeilentexts, z. B. `33,00`),
/// `HB_EXPECT_ROWS` (für `testRefresh`: nach dem Aktualisieren erwartete Zeilentexte, durch `;` getrennt,
/// z. B. `11,11;22,22`), `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`.
final class EndToEndUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddMember() throws {
        let app = try launch()
        openSection(app, "Mehr")
        let link = app.buttons["more.members"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["Mitglieder"].waitForExistence(timeout: 5))
        app.buttons["members.add"].tap()
        let username = env["HB_MEMBER_USERNAME"] ?? "anna"
        type(app.textFields["member.username"], username)
        type(app.textFields["member.displayName"], "Anna")
        type(app.secureTextFields["member.password"], try XCTUnwrap(env["HB_PASSWORD"]))
        app.buttons["member.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'members.row' AND label BEGINSWITH 'Anna,'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Anna fehlt in der Liste")
        shot("members")
    }

    /// Legt eine Ausgabe `HB_AMOUNT` an (Kategorie Lebensmittel), wartet auf den Offline-Hinweis, falls der Server aus ist.
    @MainActor
    func testAddBooking() throws {
        let app = try launch()
        let digits = try XCTUnwrap(env["HB_AMOUNT"])
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        waitUntilHittable(opener)
        opener.tap()
        let amount = app.staticTexts["quickEntry.amount"]
        if !amount.waitForExistence(timeout: 3) { opener.tap() }
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        for ch in digits { app.buttons["quickEntry.key.\(ch)"].tap() }
        let cat = app.buttons["quickEntry.category.Lebensmittel"]
        waitUntilHittable(cat)
        cat.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Sheet schließt nicht")
        Thread.sleep(forTimeInterval: 1)
        if env["HB_EXPECT_OFFLINE"] != nil {
            let banner = app.descendants(matching: .any)["syncStatusBanner"]
            XCTAssertTrue(banner.waitForExistence(timeout: 30), "Offline-Hinweis fehlt")
            print("HB_BANNER: \(banner.label)")
            XCTAssertTrue(banner.label.contains("Nicht mit NAS verbunden"), banner.label)
            XCTAssertTrue(banner.label.contains("ausstehend"), banner.label)
        } else {
            Thread.sleep(forTimeInterval: 5)
        }
        openTransactions(app)
        let added = row(app, containing: amountText(digits: digits))
        XCTAssertTrue(added.waitForExistence(timeout: 10), "Neue Buchung \(amountText(digits: digits)) fehlt in der Liste")
        shot("after-add-\(digits)")
    }

    /// Öffnet die Buchungsliste, zieht zum Aktualisieren und wartet.
    @MainActor
    func testRefresh() throws {
        let app = try launch()
        openTransactions(app)
        let list = app.collectionViews["transactions.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(app.descendants(matching: .any)["syncStatusBanner"].waitForNonExistence(timeout: 20), "Hinweis bleibt")
        // Die vom anderen Gerät erwarteten Buchungen sind angekommen.
        let expected = try XCTUnwrap(env["HB_EXPECT_ROWS"], "HB_EXPECT_ROWS fehlt")
            .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        XCTAssertFalse(expected.isEmpty, "HB_EXPECT_ROWS ist leer")
        for text in expected {
            XCTAssertTrue(row(app, containing: text).waitForExistence(timeout: 10), "Zeile \(text) fehlt nach dem Aktualisieren")
        }
        shot("list")
    }

    /// Ändert die Buchung, deren Zeile `HB_EDIT_FROM` enthält, auf `HB_AMOUNT` (Server ggf. aus).
    @MainActor
    func testEditBooking() throws {
        let app = try launch()
        openTransactions(app)
        let from = try XCTUnwrap(env["HB_EDIT_FROM"])
        let digits = try XCTUnwrap(env["HB_AMOUNT"])
        let target = row(app, containing: from)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Zeile \(from) fehlt")
        target.tap()
        let amount = app.staticTexts["edit.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        for _ in 0..<9 { app.buttons["quickEntry.key.delete"].tap() }
        for ch in digits { app.buttons["quickEntry.key.\(ch)"].tap() }
        app.buttons["edit.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Bearbeiten-Sheet schließt nicht")
        let edited = row(app, containing: amountText(digits: digits))
        XCTAssertTrue(edited.waitForExistence(timeout: 10), "Geänderte Buchung \(amountText(digits: digits)) fehlt in der Liste")
        Thread.sleep(forTimeInterval: 3)
        shot("edited-\(digits)")
    }

    /// Nur Screenshot der Buchungsliste.
    @MainActor
    func testShowList() throws {
        let app = try launch()
        openTransactions(app)
        Thread.sleep(forTimeInterval: 2)
        shot(env["HB_SHOT_NAME"] ?? "list")
    }

    /// Schnellerfassung: Tipp auf „Neu“/„+“ bis Sheet geschlossen (4 Ziffern + Kategorie), gemessen mit
    /// `XCTClockMetric` (kein Schwellwert; die Werte stehen im Testbericht). Frames werden vorab gelesen und
    /// danach nur Koordinaten getippt – näher an der reinen App-Reaktionszeit als XCUITest-Elementabfragen.
    @MainActor
    func testQuickEntryTiming() throws {
        let app = try launch()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        let amount = app.staticTexts["quickEntry.amount"]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func center(_ e: XCUIElement) -> XCUICoordinate {
            let f = e.frame
            return origin.withOffset(CGVector(dx: f.midX, dy: f.midY))
        }

        // Vorab: Frames lesen (Sheet kurz öffnen, wieder schließen ohne Speichern).
        waitUntilHittable(opener)
        opener.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        let keyFrames = [1, 2, 5, 0].map { center(app.buttons["quickEntry.key.\($0)"]) }
        let catFrame = center(app.buttons["quickEntry.category.Lebensmittel"])
        let cancel = app.buttons["Abbrechen"]
        if cancel.exists { cancel.tap() } else { app.swipeDown() }
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        let openCoord = center(opener)

        let options = XCTMeasureOptions()
        options.iterationCount = 4
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric()], options: options) {
            waitUntilHittable(opener)
            Thread.sleep(forTimeInterval: 1)
            startMeasuring()
            openCoord.tap()
            XCTAssertTrue(amount.waitForExistence(timeout: 5), "Sheet öffnet nicht")
            for k in keyFrames { k.tap() }
            catFrame.tap()
            XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "Sheet schließt nach dem Kategorie-Tipp nicht")
            stopMeasuring()
        }
        XCTAssertFalse(amount.exists, "Sheet ist noch offen")
    }

    // MARK: Hilfen

    @MainActor
    private func launch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        try requireExistence(opener, timeout: 15, "keine gespeicherte Sitzung – vorher anmelden")
        return app
    }

    @MainActor
    private func openSection(_ app: XCUIApplication, _ name: String) {
        if isPad {
            app.collectionViews.staticTexts[name].firstMatch.tap()
        } else {
            let tab = app.tabBars.buttons[name]
            waitUntilHittable(tab)
            tab.tap()
        }
    }

    @MainActor
    private func openTransactions(_ app: XCUIApplication) {
        openSection(app, "Buchungen")
        XCTAssertTrue(app.navigationBars["Buchungen"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'transactions.row' AND label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func type(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
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
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("task-14-\(prefix)-\(name).png"))
    }
}
