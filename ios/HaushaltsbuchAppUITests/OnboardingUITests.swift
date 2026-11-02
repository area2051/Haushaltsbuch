import XCTest

/// Live-Prüfung des Onboardings gegen einen laufenden Server (nicht Teil von `scripts/test.sh`).
///
/// Umgebung (über `TEST_RUNNER_`-Präfix an `xcodebuild test` übergeben):
/// - `HB_PASSWORD` (Pflicht): Passwort des Admin-Kontos (wird angelegt bzw. zum Anmelden genutzt)
/// - `HB_SERVER`: Server-Adresse, Standard `http://localhost:3000`
/// - `HB_USERNAME` / `HB_DISPLAYNAME`: Standard `admin` / `Admin`
/// - `HB_SCREENSHOT_DIR`, `HB_SCREENSHOT_PREFIX`: Screenshots als PNG dorthin schreiben
///
/// Erwartet eine frisch installierte App ohne gespeicherte Sitzung.
final class OnboardingUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    @MainActor
    func testOnboardingReachesMainNavigation() throws {
        let password = try XCTUnwrap(env["HB_PASSWORD"], "HB_PASSWORD fehlt")
        let server = env["HB_SERVER"] ?? "http://localhost:3000"
        let username = env["HB_USERNAME"] ?? "admin"
        let displayName = env["HB_DISPLAYNAME"] ?? "Admin"

        let app = XCUIApplication()
        app.launch()

        // 1. Server-Adresse
        let address = app.textFields["server.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 15), "Server-Eingabe fehlt")
        XCTAssertTrue(app.navigationBars["Server verbinden"].exists)
        shot("1-server")
        address.tap()
        address.typeText(server)
        app.buttons["server.connect"].tap()

        // 2. Einrichten oder Anmelden
        let setupUser = app.textFields["setup.username"]
        let loginUser = app.textFields["login.username"]
        let deadline = Date().addingTimeInterval(15)
        while !setupUser.exists && !loginUser.exists && Date() < deadline {
            _ = setupUser.waitForExistence(timeout: 0.5)
        }
        if setupUser.exists {
            XCTAssertTrue(app.navigationBars["Haushalt einrichten"].exists)
            shot("2-setup")
            setupUser.tap()
            setupUser.typeText(username)
            let name = app.textFields["setup.displayName"]
            name.tap()
            name.typeText(displayName)
            let pw = app.secureTextFields["setup.password"]
            pw.tap()
            pw.typeText(password)
            app.buttons["setup.submit"].tap()
        } else {
            XCTAssertTrue(loginUser.exists, "Weder Einrichtung noch Anmeldung erschienen")
            XCTAssertTrue(app.navigationBars["Anmelden"].exists)
            shot("2-login")
            loginUser.tap()
            loginUser.typeText(username)
            let pw = app.secureTextFields["login.password"]
            pw.tap()
            pw.typeText(password)
            app.buttons["login.submit"].tap()
        }

        // 3. Hauptansicht
        if UIDevice.current.userInterfaceIdiom == .pad {
            let addButton = app.buttons["toolbar.add"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 15), "Toolbar-„+“ fehlt")
            for title in ["Übersicht", "Buchungen", "Budgets", "Mehr"] {
                XCTAssertTrue(app.collectionViews.staticTexts[title].exists, "Seitenleiste ohne \(title)")
            }
            shot("3-main")
            addButton.tap()
            XCTAssertTrue(app.navigationBars["Neue Buchung"].waitForExistence(timeout: 5))
            shot("4-entry")
            app.buttons["Abbrechen"].tap()
        } else {
            let overview = app.tabBars.buttons["Übersicht"]
            XCTAssertTrue(overview.waitForExistence(timeout: 15), "Tab-Leiste fehlt")
            for title in ["Buchungen", "Neu", "Budgets", "Mehr"] {
                XCTAssertTrue(app.tabBars.buttons[title].exists, "Tab \(title) fehlt")
            }
            // Direkt nach der Anmeldung läuft noch die Übergangsanimation (Tastatur); ein Tipp kann
            // verloren gehen. Erst warten, bis der Tab bedienbar ist, dann ggf. einmal wiederholen.
            let transactions = app.tabBars.buttons["Buchungen"]
            waitUntilHittable(transactions)
            transactions.tap()
            if !app.navigationBars["Buchungen"].waitForExistence(timeout: 3) {
                print("HB-UITEST: Tab-Tipp wiederholt")
                transactions.tap()
            }
            XCTAssertTrue(app.navigationBars["Buchungen"].waitForExistence(timeout: 5))
            shot("3-main")
            app.tabBars.buttons["Neu"].tap()
            XCTAssertTrue(app.navigationBars["Neue Buchung"].waitForExistence(timeout: 5))
            shot("4-entry")
            app.buttons["Abbrechen"].tap()
            // Zurück auf dem vorherigen Tab.
            XCTAssertTrue(app.navigationBars["Buchungen"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.buttons["Buchungen"].isSelected)
        }
    }

    /// Bei bestehender Sitzung (Schlüsselbund): Start direkt in der Hauptansicht, ein einzelner
    /// Tipp wechselt den Tab. Ohne Sitzung schlägt der Test fehl.
    @MainActor
    func testRelaunchStaysLoggedInAndTabsSwitchOnFirstTap() throws {
        let app = XCUIApplication()
        app.launch()
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("nur iPhone") }
        let budgets = app.tabBars.buttons["Budgets"]
        try requireExistence(budgets, timeout: 10, "keine gespeicherte Sitzung – vorher anmelden")
        waitUntilHittable(budgets)
        budgets.tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 3), "erster Tipp verloren")
    }

    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
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
        let url = URL(fileURLWithPath: dir).appendingPathComponent("task-9-\(prefix)-\(name).png")
        try? png.write(to: url)
    }
}
