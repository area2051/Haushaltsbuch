import Foundation
import SwiftData
import SwiftUI
import Testing
import HaushaltsbuchData
@testable import HaushaltsbuchUI

// MARK: Phasen & Login

@MainActor @Test func startsInOnboardingWithoutSession() throws {
    let f = try AppFixture()
    #expect(f.model.phase == .onboarding)
    #expect(f.model.engine == nil)
    #expect(f.schedulers.isEmpty)
}

@MainActor @Test func readyAfterLoginAndStartsScheduler() async throws {
    let f = try AppFixture()
    f.transport.enqueue("getHealth", AppFixtures.health(setupRequired: false))
    try await f.model.connect(serverInput: "  nas.local:3000 ")
    #expect(f.auth.state == .needsLogin(AppFixtures.serverURL))
    #expect(f.model.phase == .onboarding)

    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.annaId, username: "anna"))
    let outcome = try await f.model.login(username: "anna", password: "geheim123")

    #expect(outcome == .loggedIn)
    #expect(f.model.phase == .ready)
    #expect(f.model.engine != nil)
    let scheduler = try #require(f.schedulers.only)
    #expect(scheduler.starts == 1)
    #expect(f.cursors.keys.contains(UserDefaultsCursorStore.key(serverURL: AppFixtures.serverURL,
                                                                userId: AppFixtures.annaId)))

    // Repository-Änderungen und Vordergrund lösen den Scheduler aus.
    try f.addPendingTransaction()
    #expect(scheduler.localChanges == 2)
    f.model.scenePhaseChanged(.active)
    #expect(scheduler.activations == 1)
    f.model.scenePhaseChanged(.background)
    #expect(scheduler.activations == 1)
}

@MainActor @Test func restoredSessionIsReadyImmediately() throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    #expect(f.model.phase == .ready)
    #expect(f.schedulers.only?.starts == 1)
}

@MainActor @Test func setupLogsInAndStartsScheduler() async throws {
    let f = try AppFixture()
    f.transport.enqueue("getHealth", AppFixtures.health(setupRequired: true))
    try await f.model.connect(serverInput: "http://nas.local:3000")
    #expect(f.auth.state == .needsSetup(AppFixtures.serverURL))

    f.transport.enqueue("setup", .json(201, #"{"user":{"id":"0f8fad5b-d9cb-469f-a165-70867728950e","username":"anna","displayName":"Anna","isAdmin":true}}"#))
    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.annaId, username: "anna"))
    let outcome = try await f.model.setup(username: "anna", displayName: "Anna", password: "geheim123")

    #expect(outcome == .loggedIn)
    #expect(f.model.phase == .ready)
    #expect(f.schedulers.only?.starts == 1)
}

@MainActor @Test func invalidServerInputThrows() async throws {
    let f = try AppFixture()
    await #expect(throws: AppModel.InputError.invalidServerURL) {
        try await f.model.connect(serverInput: "   ")
    }
    #expect(f.transport.calls("getHealth") == 0)
}

// MARK: Ablauf der Sitzung

@MainActor @Test func expiredSessionKeepsLocalData() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna", realSyncTransport: true)
    #expect(f.model.phase == .ready)
    try f.addPendingTransaction()
    let scheduler = try #require(f.schedulers.only)

    // Access-Token abgelaufen, Refresh-Token ungültig → AuthService verwirft die Sitzung.
    f.transport.enqueue("sync", AppFixtures.error(401, code: "unauthorized"))
    f.transport.enqueue("refresh", AppFixtures.error(401, code: "invalid_refresh_token"))
    await f.model.engine?.syncNow()
    await waitUntil { f.model.phase == .locked }

    #expect(f.model.phase == .locked)
    #expect(f.auth.state == .needsLogin(AppFixtures.serverURL))
    #expect(scheduler.stops == 1)
    #expect(f.model.engine == nil)
    #expect(f.model.loginPrefill == "anna")
    #expect(try f.count(TransactionEntity.self) == 1)
    #expect(f.model.repository.pendingChangesCount == 2)

    // Gleicher Benutzer meldet sich wieder an: keine Rückfrage, Daten bleiben, neuer Scheduler.
    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.annaId, username: "anna"))
    let outcome = try await f.model.login(username: "Anna", password: "geheim123")
    #expect(outcome == .loggedIn)
    #expect(f.model.phase == .ready)
    #expect(try f.count(TransactionEntity.self) == 1)
    #expect(f.schedulers.count == 2)
    #expect(f.schedulers.last?.starts == 1)
}

// MARK: Benutzerwechsel

@MainActor @Test func switchingUserWithPendingChangesRequiresConfirmation() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    try f.addPendingTransaction()
    f.cursor(AppFixtures.serverURL, AppFixtures.bertId).lastVersion = 42

    // Sitzung abgelaufen (Refresh-Token ungültig) → Daten bleiben, Anmeldung gesperrt.
    await f.expireSession()
    #expect(f.model.phase == .locked)
    #expect(f.schedulers.only?.stops == 1)

    let first = try await f.model.login(username: "bert", password: "geheim123")
    #expect(first == .needsDiscardConfirmation(pending: 2))
    #expect(f.transport.calls("login") == 0)
    #expect(try f.count(TransactionEntity.self) == 1)
    #expect(f.model.phase == .locked)

    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.bertId, username: "bert"))
    let second = try await f.model.login(username: "bert", password: "geheim123", discardPending: true)
    #expect(second == .loggedIn)
    #expect(f.model.phase == .ready)
    #expect(try f.count(TransactionEntity.self) == 0)
    #expect(try f.count(CategoryEntity.self) == 0)
    #expect(f.cursor(AppFixtures.serverURL, AppFixtures.bertId).lastVersion == 0)
    #expect(f.schedulers.last?.starts == 1)
}

@MainActor @Test func switchingUserWithoutPendingChangesWipesSilently() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    f.syncTransport.isOnline = true
    let ctx = f.container.mainContext
    ctx.insert(MemberEntity(id: AppFixtures.annaId, username: "anna", displayName: "Anna", isAdmin: true, version: 1))
    try ctx.save()

    await f.expireSession()
    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.bertId, username: "bert"))
    let outcome = try await f.model.login(username: "bert", password: "geheim123")

    #expect(outcome == .loggedIn)
    #expect(try f.count(MemberEntity.self) == 0)
}

@MainActor @Test func failedSwitchLoginKeepsLocalData() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    try f.addPendingTransaction()
    await f.expireSession()

    f.transport.enqueue("login", AppFixtures.error(401, code: "invalid_credentials"))
    await #expect(throws: APIError.self) {
        try await f.model.login(username: "bert", password: "falsch", discardPending: true)
    }
    #expect(try f.count(TransactionEntity.self) == 1)
    #expect(f.model.phase == .locked)
}

// MARK: Abmelden (Task 13): Rückfrage bei ungesendeten Änderungen, dann Store leeren

@MainActor @Test func logoutWithPendingChangesAsksForConfirmation() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    try f.addPendingTransaction()
    f.cursor(AppFixtures.serverURL, AppFixtures.annaId).lastVersion = 42

    // Offline: Sync scheitert, Änderungen bleiben → Rückfrage, noch nichts passiert.
    let first = await f.model.logout()
    #expect(first == .needsDiscardConfirmation(pending: 2))
    #expect(f.syncTransport.requests == 1)
    #expect(f.model.phase == .ready)
    #expect(f.model.engine != nil)
    #expect(f.store.load() != nil)
    #expect(f.transport.calls("logout") == 0)
    #expect(try f.count(TransactionEntity.self) == 1)

    // Temporäre Exportdatei wird beim Abmelden mit gelöscht.
    try FileManager.default.createDirectory(at: ExportModel.directory, withIntermediateDirectories: true)
    let exportFile = ExportModel.directory.appendingPathComponent("Haushaltsbuch_test.csv")
    try Data("x".utf8).write(to: exportFile)
    #expect(f.defaults.string(forKey: AppModel.dataUsernameKey) == "anna")
    #expect(f.defaults.url(forKey: AppModel.dataServerKey) == AppFixtures.serverURL)

    f.transport.enqueue("logout", .empty(204))
    let second = await f.model.logout(discardPending: true)
    #expect(second == .loggedOut)
    #expect(f.syncTransport.requests == 1)               // nach Bestätigung kein zweiter Sync-Versuch
    #expect(!FileManager.default.fileExists(atPath: exportFile.path))
    #expect(f.defaults.string(forKey: AppModel.dataUsernameKey) == nil)
    #expect(f.defaults.url(forKey: AppModel.dataServerKey) == nil)
    #expect(f.model.phase == .locked)
    #expect(f.model.engine == nil)
    #expect(f.store.load() == nil)
    #expect(f.transport.calls("logout") == 1)
    #expect(try f.count(TransactionEntity.self) == 0)
    #expect(try f.count(CategoryEntity.self) == 0)
    #expect(f.cursor(AppFixtures.serverURL, AppFixtures.annaId).lastVersion == 0)
}

@MainActor @Test func logoutWithoutPendingChangesWipesAndAllowsOtherUser() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    f.syncTransport.isOnline = true
    let ctx = f.container.mainContext
    ctx.insert(MemberEntity(id: AppFixtures.annaId, username: "anna", displayName: "Anna", isAdmin: true, version: 1))
    try ctx.save()
    f.cursor(AppFixtures.serverURL, AppFixtures.annaId).lastVersion = 42

    f.transport.enqueue("logout", .empty(204))
    #expect(await f.model.logout() == .loggedOut)
    #expect(f.model.phase == .locked)
    #expect(try f.count(MemberEntity.self) == 0)
    #expect(f.cursor(AppFixtures.serverURL, AppFixtures.annaId).lastVersion == 0)

    // Store ist leer: ein anderer Benutzer braucht keine Rückfrage.
    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.bertId, username: "bert"))
    #expect(try await f.model.login(username: "bert", password: "geheim123") == .loggedIn)
    #expect(f.model.phase == .ready)
}

/// Leeren scheitert: Daten und Besitzer-Schlüssel bleiben (ein anderer Benutzer löst dann den
/// Wechsel-Ablauf mit Rückfrage aus), abgemeldet wird trotzdem.
@MainActor @Test func logoutWipeFailureKeepsDataAndOwnerKeys() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna",
                           wipe: { _, _ in throw WipeFailure() })
    try f.addPendingTransaction()
    f.transport.enqueue("logout", .empty(204))
    #expect(await f.model.logout(discardPending: true) == .loggedOut)
    #expect(f.model.phase == .locked)
    #expect(f.store.load() == nil)
    #expect(try f.count(TransactionEntity.self) == 1)
    #expect(f.defaults.string(forKey: AppModel.dataUsernameKey) == "anna")
    #expect(f.defaults.url(forKey: AppModel.dataServerKey) == AppFixtures.serverURL)
    let other = try await f.model.login(username: "bert", password: "geheim123")
    #expect(other == .needsDiscardConfirmation(pending: 2))
}

@MainActor @Test func logoutKeepsAppLockSetting() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    f.syncTransport.isOnline = true
    f.defaults.set(true, forKey: AppLock.enabledKey)
    f.transport.enqueue("logout", .empty(204))
    #expect(await f.model.logout() == .loggedOut)
    #expect(f.defaults.bool(forKey: AppLock.enabledKey))
}

// MARK: Fix-Runde 1: sicherer Wechsel, begrenztes Abmelden

struct WipeFailure: Error {}

@MainActor @Test func switchKeepsLoginScreenUntilWipeSucceeded() async throws {
    var phaseDuringWipe: AppModel.Phase?
    var authDuringWipe: AuthState?
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna", wipe: { model, context in
        phaseDuringWipe = model.phase
        authDuringWipe = model.auth.state
        try AppModel.deleteAllRecords(in: context)
    })
    try f.addPendingTransaction()
    await f.expireSession()

    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.bertId, username: "bert"))
    let outcome = try await f.model.login(username: "bert", password: "geheim123", discardPending: true)

    // Beim Leeren ist Bert schon angemeldet, die Oberfläche zeigt aber weiter die Anmeldung.
    guard case .loggedIn = try #require(authDuringWipe) else { Issue.record("nicht angemeldet"); return }
    #expect(phaseDuringWipe == .locked)
    #expect(outcome == .loggedIn)
    #expect(f.model.phase == .ready)
}

@MainActor @Test func failedWipeLogsOutAgainAndKeepsSwitchPending() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna",
                           wipe: { _, _ in throw WipeFailure() })
    try f.addPendingTransaction()
    await f.expireSession()
    let schedulersBefore = f.schedulers.count

    f.transport.enqueue("login", AppFixtures.loginOK(id: AppFixtures.bertId, username: "bert"))
    f.transport.enqueue("logout", .empty(204))
    await #expect(throws: AppModel.SwitchError.localDataNotCleared) {
        try await f.model.login(username: "bert", password: "geheim123", discardPending: true)
    }

    #expect(AppModel.SwitchError.localDataNotCleared.germanMessage
            == "Lokale Daten konnten nicht gelöscht werden. Bitte erneut versuchen.")
    #expect(f.store.load() == nil)                       // neue Sitzung verworfen
    #expect(f.transport.calls("logout") == 1)            // Bert-Refresh-Token widerrufen
    #expect(f.model.phase == .locked)
    #expect(f.model.engine == nil)
    #expect(f.schedulers.count == schedulersBefore)      // kein Sync auf Annas Daten
    #expect(try f.count(TransactionEntity.self) == 1)
    // Bert ist jetzt `lastUsername`, die Daten gehören aber weiter Anna → erneut Rückfrage.
    let retry = try await f.model.login(username: "bert", password: "geheim123")
    #expect(retry == .needsDiscardConfirmation(pending: 2))
}

@MainActor @Test func logoutSyncIsBounded() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna",
                           hangingSync: true, logoutSyncTimeout: 0.05)
    f.transport.enqueue("logout", .empty(204))
    let start = ContinuousClock.now
    #expect(await f.model.logout() == .loggedOut)
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(f.model.phase == .locked)
    #expect(f.store.load() == nil)
}

@MainActor @Test func runBoundedReturnsEarlyWhenWorkFinishes() async {
    let start = ContinuousClock.now
    var ran = false
    await AppModel.runBounded(seconds: 10) { ran = true }
    #expect(ran)
    #expect(ContinuousClock.now - start < .seconds(2))
}

// MARK: Final-Review: Verwerfen abgelehnter synchronisierter Änderungen

@MainActor @Test func discardingRejectedSyncedChangeResetsCursorAndSyncs() async throws {
    let f = try AppFixture(session: AppFixtures.session(), lastUsername: "anna")
    let scheduler = try #require(f.schedulers.only)
    let cursor = f.cursor(AppFixtures.serverURL, AppFixtures.annaId)
    let tx = try f.addPendingTransaction()
    tx.version = 5
    tx.isDirty = false
    tx.rejectionReason = "unknown_user"
    cursor.lastVersion = 42

    try f.model.repository.discardRejected(tx)

    #expect(cursor.lastVersion == 0)
    #expect(scheduler.syncRequests == 1)
    #expect(tx.rejectionReason == nil)
}

// MARK: Hilfsfunktionen

@Test func normalizesServerInput() {
    #expect(AppModel.normalizeServerURL("nas.local:3000") == URL(string: "http://nas.local:3000"))
    #expect(AppModel.normalizeServerURL(" http://10.0.0.2:3000/ \n") == URL(string: "http://10.0.0.2:3000/"))
    #expect(AppModel.normalizeServerURL("https://nas.example.org") == URL(string: "https://nas.example.org"))
    #expect(AppModel.normalizeServerURL("") == nil)
    #expect(AppModel.normalizeServerURL("http://") == nil)
    #expect(AppModel.normalizeServerURL("ftp://nas.local") == nil)
}

@Test func bannerTextOnlyForProblems() {
    #expect(SyncStatusBanner.message(for: .idle) == nil)
    #expect(SyncStatusBanner.message(for: .syncing) == nil)
    #expect(SyncStatusBanner.message(for: .upToDate(Date())) == nil)
    #expect(SyncStatusBanner.message(for: .offline(pending: 3)) == "Nicht mit NAS verbunden – 3 Änderungen ausstehend")
    #expect(SyncStatusBanner.message(for: .offline(pending: 1)) == "Nicht mit NAS verbunden – 1 Änderung ausstehend")
    #expect(SyncStatusBanner.message(for: .error("x", pending: 0)) == "Nicht mit NAS verbunden – 0 Änderungen ausstehend")
}

extension Array {
    /// Das einzige Element, sonst `nil`.
    var only: Element? { count == 1 ? first : nil }
}
