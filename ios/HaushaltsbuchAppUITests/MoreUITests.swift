import XCTest

/// Live-Prüfung von „Mehr“ (setzt eine gespeicherte Admin-Sitzung voraus; nicht Teil von `scripts/test.sh`).
/// Einzelne Schritte über `-only-testing:HaushaltsbuchAppUITests/MoreUITests/<test>`.
/// Umgebung: `HB_PASSWORD` (Passwort für das neue Mitglied), `HB_MEMBER_USERNAME` (Standard `bert`),
/// `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`.
final class MoreUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUp() {
        continueAfterFailure = false
    }

    /// Nach dem Abmelden (Anmeldebildschirm mit vorausgefülltem Benutzer) wieder anmelden.
    @MainActor
    func test0Login() throws {
        let app = XCUIApplication()
        app.launch()
        let pw = app.secureTextFields["login.password"]
        try requireExistence(pw, timeout: 10, "kein Anmeldebildschirm – vorher abmelden")
        type(pw, try XCTUnwrap(env["HB_PASSWORD"]))
        app.buttons["login.submit"].tap()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "Anmeldung fehlgeschlagen")
        Thread.sleep(forTimeInterval: 3)
    }

    /// Sperre an, Buchungen öffnen, Home: danach den App-Umschalter von außen öffnen und prüfen,
    /// dass der Schnappschuss den Sperrbildschirm zeigt.
    @MainActor
    func test7SwitcherPrep() throws {
        let app = try launch()
        openSection(app, "Mehr")
        let toggle = app.switches["more.faceID"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        openSection(app, "Buchungen")
        XCTAssertTrue(app.navigationBars["Buchungen"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) { search.tap() }   // Fokus/Tastatur offen
        Thread.sleep(forTimeInterval: 1)
        shot("switcher-0-before-home")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor
    func test1Members() throws {
        let app = try launch()
        openMore(app, "more.members", title: "Mitglieder")
        XCTAssertTrue(app.buttons.matching(identifier: "members.row").firstMatch.waitForExistence(timeout: 10))
        // Entfernte Benutzernamen bleiben auf dem Server belegt (Soft-Delete) → für Wiederholungen änderbar.
        let username = env["HB_MEMBER_USERNAME"] ?? "bert"
        let bert = memberRow(app, "Bert")
        if !bert.exists {
            app.buttons["members.add"].tap()
            type(app.textFields["member.username"], username)
            type(app.textFields["member.displayName"], "Bert")
            type(app.secureTextFields["member.password"], try XCTUnwrap(env["HB_PASSWORD"]))
            shot("members-1-new")
            app.buttons["member.save"].tap()
            XCTAssertTrue(bert.waitForExistence(timeout: 10), "Bert fehlt in der Liste")
        }
        Thread.sleep(forTimeInterval: 2)
        shot("members-2-list")

        // Doppelter Benutzername → deutsche Fehlermeldung
        waitUntilHittable(app.buttons["members.add"])
        app.buttons["members.add"].tap()
        type(app.textFields["member.username"], username)
        type(app.textFields["member.displayName"], "Bert 2")
        type(app.secureTextFields["member.password"], try XCTUnwrap(env["HB_PASSWORD"]))
        app.buttons["member.save"].tap()
        XCTAssertTrue(app.staticTexts["Benutzername ist bereits vergeben."].waitForExistence(timeout: 10))
        shot("members-3-taken")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.staticTexts["member.error"].waitForNonExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        waitUntilHittable(bert)
        bert.tap()
        app.buttons["member.remove"].tap()
        let confirm = app.buttons["Entfernen"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("members-4-confirm-remove")
        confirm.tap()
        XCTAssertTrue(bert.waitForNonExistence(timeout: 10), "Bert bleibt in der Liste")
        shot("members-5-removed")
    }

    @MainActor
    func test2RecurringRule() throws {
        let app = try launch()
        openMore(app, "more.rules", title: "Wiederkehrende")
        app.buttons["rules.add"].tap()
        XCTAssertTrue(app.staticTexts["rule.amount"].waitForExistence(timeout: 5))
        for digit in [8, 5, 0, 0, 0] { app.buttons["quickEntry.key.\(digit)"].tap() }
        app.buttons["quickEntry.category.Wohnen"].tap()
        type(app.textFields["rule.note"], "Miete")
        shot("rules-1-new")
        app.buttons["rule.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'rules.row' AND label CONTAINS 'Miete'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        shot("rules-2-list-before-sync")

        // Sync nach 2 s sendet die Regel; der Server erzeugt die Buchung, der nächste Sync holt sie.
        Thread.sleep(forTimeInterval: 5)
        pullToRefresh(app, app.collectionViews["rules.list"])
        Thread.sleep(forTimeInterval: 4)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Nächster Termin: 02.12.2026'")).firstMatch.exists
                      || row.label.contains("02.12.2026"), "Nächster Termin nicht vom Server gesetzt: \(row.label)")
        shot("rules-3-list-after-sync")

        openSection(app, "Buchungen")
        let tx = app.buttons.matching(NSPredicate(format: "identifier == 'transactions.row' AND label CONTAINS 'Miete'")).firstMatch
        if !tx.waitForExistence(timeout: 5) {
            pullToRefresh(app, app.collectionViews["transactions.list"])
        }
        XCTAssertTrue(tx.waitForExistence(timeout: 10), "Erzeugte Buchung fehlt")
        shot("rules-4-generated-transaction")
    }

    @MainActor
    func test3Export() throws {
        let app = try launch()
        openMore(app, "more.export", title: "CSV-Export")
        let share = app.buttons["export.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        shot("export-1-form")
        share.tap()
        // Teilen-Menü (System); Dateiname im Vorschaukopf.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        _ = sheet.waitForExistence(timeout: 10)
        Thread.sleep(forTimeInterval: 2)
        shot("export-2-share-sheet")
        let saveToFiles = app.buttons["In „Dateien“ sichern"].firstMatch
        if saveToFiles.waitForExistence(timeout: 3) {
            saveToFiles.tap()
            Thread.sleep(forTimeInterval: 3)
            shot("export-3-save-to-files")
            let save = app.buttons["Sichern"].firstMatch
            if save.waitForExistence(timeout: 5) { save.tap() }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    @MainActor
    func test4ServerStatus() throws {
        let app = try launch()
        openMore(app, "more.server", title: "Server & Sync")
        XCTAssertTrue(app.staticTexts["server.user"].waitForExistence(timeout: 5))
        app.buttons["server.syncNow"].tap()
        Thread.sleep(forTimeInterval: 3)
        shot("server-1-status")
    }

    /// Schaltet die Sperre ein, geht in den Hintergrund und zurück. Entsperren übernimmt die
    /// Shell (`notifyutil … pearl.match`) während der Test bis zu 60 s wartet.
    @MainActor
    func test5AppLock() throws {
        let app = try launch()
        openMore(app, "more.server", title: "Server & Sync")   // nur um sicher in „Mehr“ zu sein
        app.navigationBars.buttons.firstMatch.tap()
        let toggle = app.switches["more.faceID"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.tap() }
        Thread.sleep(forTimeInterval: 1)
        shot("lock-1-enabled")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        let lockScreen = app.descendants(matching: .any)["lockScreen"]
        XCTAssertTrue(lockScreen.waitForExistence(timeout: 10), "Sperrbildschirm fehlt")
        Thread.sleep(forTimeInterval: 2)
        shot("lock-2-locked-with-prompt")
        print("HB_LOCK_READY")
        XCTAssertTrue(lockScreen.waitForNonExistence(timeout: 60), "Nicht entsperrt")
        shot("lock-3-unlocked")
        // Wieder ausschalten (Gerätezustand für weitere Läufe)
        if (toggle.value as? String) == "1" { toggle.switches.firstMatch.tap() }
    }

    /// Server vorher stoppen: eine Buchung bleibt ungesendet → Abmelden fragt nach.
    @MainActor
    func test6LogoutWithPending() throws {
        let app = try launch()
        let opener = isPad ? app.buttons["toolbar.add"] : app.tabBars.buttons["Neu"]
        opener.tap()
        XCTAssertTrue(app.staticTexts["quickEntry.amount"].waitForExistence(timeout: 5))
        for digit in [1, 5, 0] { app.buttons["quickEntry.key.\(digit)"].tap() }
        app.buttons["quickEntry.category.Lebensmittel"].tap()
        Thread.sleep(forTimeInterval: 1)
        openSection(app, "Mehr")
        app.buttons["more.logout"].tap()
        let warning = app.staticTexts.matching(NSPredicate(format: "label MATCHES '[0-9]+ ungesendete Änderung(en)? geh(t|en) verloren'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 15), "Rückfrage fehlt")
        shot("logout-1-confirmation")
        // Popover (iOS 26) hat kein „Abbrechen“: daneben tippen.
        if app.buttons["Abbrechen"].exists {
            app.buttons["Abbrechen"].firstMatch.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        }
        XCTAssertTrue(warning.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["more.logout"].isHittable, "Abbrechen meldet nicht ab")
        shot("logout-2-cancelled-still-logged-in")
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
    private func openMore(_ app: XCUIApplication, _ identifier: String, title: String) {
        openSection(app, "Mehr")
        let link = app.buttons[identifier]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "\(identifier) fehlt")
        link.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) öffnet nicht")
    }

    @MainActor
    private func memberRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'members.row' AND label BEGINSWITH %@", name + ",")).firstMatch
    }

    @MainActor
    private func type(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func pullToRefresh(_ app: XCUIApplication, _ list: XCUIElement) {
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
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
        let prefix = env["HB_SCREENSHOT_PREFIX"] ?? "iphone"
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("task-13-\(prefix)-\(name).png"))
    }
}
