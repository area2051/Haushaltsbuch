import Foundation
import Observation
import os
import SwiftData
import SwiftUI
import HaushaltsbuchAPI
import HaushaltsbuchData

private let logger = Logger(subsystem: "de.haushaltsbuch.app", category: "app")

/// Was das `AppModel` vom Scheduler braucht (Tests ersetzen ihn).
@MainActor
public protocol SyncScheduling: AnyObject {
    func start()
    func stop()
    func appDidBecomeActive()
    func localChange()
    func pullToRefresh() async
}

extension SyncScheduler: SyncScheduling {}

/// Verdrahtet Store, Repository, Anmeldung und Sync für die Oberfläche.
///
/// - `phase` folgt `auth.state`: ohne Sitzung `.onboarding`, nach Ablauf/Abmelden eines bekannten
///   Benutzers `.locked` (Anmeldung vorausgefüllt, lokale Daten bleiben), angemeldet `.ready`.
/// - Bei jeder (neuen) Sitzung entstehen `SyncEngine` + `SyncScheduler` für Server und Benutzer;
///   ohne Sitzung werden sie gestoppt und verworfen. Das gilt auch, wenn der `AuthService` die
///   Sitzung selbst verwirft (Refresh-Token ungültig) – das Modell beobachtet `auth.state`.
/// - Repository-Änderungen → `scheduler.localChange()`, Vordergrund → `appDidBecomeActive()`.
///
/// `@Observable` (wie `AuthService`) statt `ObservableObject`: `phase` ist aus `auth.state`
/// berechnet und wird von SwiftUI dadurch automatisch mitbeobachtet.
@MainActor @Observable
public final class AppModel {
    public enum Phase: Equatable, Sendable {
        case onboarding
        case locked
        case ready
    }

    public enum LogoutOutcome: Equatable, Sendable {
        case loggedOut
        /// Nach dem Sync-Versuch noch ungesendete Änderungen: erst nach Bestätigung verwerfen.
        case needsDiscardConfirmation(pending: Int)
    }

    public enum AuthOutcome: Equatable, Sendable {
        case loggedIn
        /// Anderer Benutzer/Server, aber ungesendete Änderungen: erst nach Bestätigung verwerfen.
        case needsDiscardConfirmation(pending: Int)
    }

    /// Benutzerwechsel gescheitert: alte Daten nicht gelöscht, die neue Sitzung wurde verworfen.
    public enum SwitchError: Error, Equatable {
        case localDataNotCleared

        public var germanMessage: String {
            switch self {
            case .localDataNotCleared: "Lokale Daten konnten nicht gelöscht werden. Bitte erneut versuchen."
            }
        }
    }

    public enum InputError: Error, Equatable {
        case invalidServerURL

        public var germanMessage: String {
            switch self {
            case .invalidServerURL: "Bitte eine gültige Server-Adresse eingeben, z. B. http://nas.local:3000."
            }
        }
    }

    /// Fabriken für die Sync-Bausteine einer Sitzung (Tests übergeben Fakes).
    public struct Dependencies {
        public var makeTransport: @MainActor (Client) -> any SyncTransport
        public var makeCursor: @MainActor (URL, UUID) -> any SyncCursorStore
        public var makeScheduler: @MainActor (SyncEngine) -> any SyncScheduling
        /// Leert den lokalen Store beim Benutzerwechsel (Tests lassen es scheitern).
        public var wipeStore: @MainActor (ModelContext) throws -> Void
        /// Höchstdauer des Syncs vor dem Abmelden (offline sonst bis zum Request-Timeout).
        public var logoutSyncTimeout: Double

        public init(makeTransport: @escaping @MainActor (Client) -> any SyncTransport,
                    makeCursor: @escaping @MainActor (URL, UUID) -> any SyncCursorStore,
                    makeScheduler: @escaping @MainActor (SyncEngine) -> any SyncScheduling,
                    wipeStore: @escaping @MainActor (ModelContext) throws -> Void = { try AppModel.deleteAllRecords(in: $0) },
                    logoutSyncTimeout: Double = 5) {
            self.makeTransport = makeTransport
            self.makeCursor = makeCursor
            self.makeScheduler = makeScheduler
            self.wipeStore = wipeStore
            self.logoutSyncTimeout = logoutSyncTimeout
        }

        public static func live(defaults: UserDefaults = .standard) -> Dependencies {
            // UserDefaults ist thread-sicher, im SDK aber nicht `Sendable` markiert.
            nonisolated(unsafe) let defaults = defaults
            return Dependencies(
                makeTransport: { ClientSyncTransport(client: $0) },
                makeCursor: { UserDefaultsCursorStore(serverURL: $0, userId: $1, defaults: defaults) },
                makeScheduler: { SyncScheduler(engine: $0) })
        }
    }

    /// Server und Benutzer, deren Daten im lokalen Store liegen (Wechsel-Erkennung). Eigene Schlüssel
    /// statt `auth.lastUsername`: der wird schon beim Anmelden überschrieben, auch wenn das Leeren
    /// danach scheitert.
    static let dataServerKey = "app.dataServerURL"
    static let dataUsernameKey = "app.dataUsername"

    @ObservationIgnored public let container: ModelContainer
    @ObservationIgnored public private(set) var repository: Repository!
    public let auth: AuthService
    public private(set) var engine: SyncEngine?
    /// Face-ID-Sperre (Geräteeinstellung, unabhängig von der Sitzung).
    @ObservationIgnored public let appLock: AppLock

    @ObservationIgnored private var scheduler: (any SyncScheduling)?
    @ObservationIgnored private var activeSession: SessionKey?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dependencies: Dependencies
    /// Während eines Benutzerwechsels: Sitzung erst nach dem Leeren des Stores aktivieren.
    @ObservationIgnored private var holdActivation = false
    /// Während eines Benutzerwechsels der Anmeldezustand von vorher: die Oberfläche bleibt auf dem
    /// Anmelde-/Einrichtungsbildschirm, bis die alten Daten gelöscht sind (beobachtet).
    private var frozenAuthState: AuthState?

    private struct SessionKey: Equatable {
        let serverURL: URL
        let userId: UUID
    }

    public init(container: ModelContainer, auth: AuthService, defaults: UserDefaults = .standard,
                dependencies: Dependencies? = nil, appLock: AppLock? = nil) {
        self.container = container
        self.auth = auth
        self.defaults = defaults
        self.appLock = appLock ?? AppLock(defaults: defaults)
        self.dependencies = dependencies ?? .live(defaults: defaults)
        repository = Repository(context: container.mainContext) { [weak self] in
            self?.scheduler?.localChange()
        }
        authStateChanged()
        observeAuth()
    }

    // MARK: Zustand

    /// Anmeldezustand, den die Oberfläche zeigt (während eines Benutzerwechsels der vorherige).
    public var visibleAuthState: AuthState {
        frozenAuthState ?? auth.state
    }

    /// Angemeldete Sitzung (Server & Sync, Admin-Rechte).
    public var session: StoredSession? {
        if case .loggedIn(let session) = auth.state { session } else { nil }
    }

    /// Eingeloggter Benutzer (für „Bezahlt von“ und Vorbelegungen).
    public var currentUserId: UUID? {
        if case .loggedIn(let session) = auth.state { session.userId } else { nil }
    }

    public var phase: Phase {
        switch visibleAuthState {
        case .loggedIn:
            .ready
        case .needsLogin:
            auth.lastUsername == nil ? .onboarding : .locked
        case .needsServer, .needsSetup:
            .onboarding
        }
    }

    /// Benutzername zum Vorausfüllen der Anmeldung.
    public var loginPrefill: String {
        auth.lastUsername ?? ""
    }

    // MARK: Aktionen der Oberfläche

    /// Server-Adresse prüfen und verbinden (`GET /health`).
    public func connect(serverInput: String) async throws {
        guard let url = Self.normalizeServerURL(serverInput) else { throw InputError.invalidServerURL }
        try await auth.connect(to: url)
    }

    public func setup(username: String, displayName: String, password: String,
                      discardPending: Bool = false) async throws -> AuthOutcome {
        try await authenticate(username: username, discardPending: discardPending) {
            try await self.auth.setup(username: username, displayName: displayName, password: password)
        }
    }

    public func login(username: String, password: String,
                      discardPending: Bool = false) async throws -> AuthOutcome {
        try await authenticate(username: username, discardPending: discardPending) {
            try await self.auth.login(username: username, password: password)
        }
    }

    /// Zurück zur Server-Eingabe („Anderen Server wählen“).
    public func chooseOtherServer() {
        auth.forgetServer()
    }

    /// Abmelden (Spec §7 „Mehr“): vorher noch einmal synchronisieren (höchstens
    /// `logoutSyncTimeout`). Bleiben ungesendete Änderungen, passiert nichts und die Oberfläche
    /// fragt nach (`needsDiscardConfirmation`); mit `discardPending` werden sie ohne erneuten
    /// Sync-Versuch verworfen. Danach: Sitzung beim Server beenden, lokalen Store leeren,
    /// Sync-Cursor zurücksetzen, temporäre Exportdateien löschen.
    ///
    /// Läuft dagegen nur die Sitzung ab (Refresh-Token ungültig), bleiben die Daten erhalten (§8).
    public func logout(discardPending: Bool = false) async -> LogoutOutcome {
        // Nach der Bestätigung nicht erneut warten: der Sync-Versuch lief schon beim ersten Aufruf.
        if !discardPending, let engine {
            await Self.runBounded(seconds: dependencies.logoutSyncTimeout) {
                await engine.syncNow()
            }
        }
        let pending = repository.pendingChangesCount
        if pending > 0 && !discardPending {
            return .needsDiscardConfirmation(pending: pending)
        }
        let session = self.session
        deactivate()
        await auth.logout()
        ExportModel.removeTemporaryFiles()
        do {
            try dependencies.wipeStore(container.mainContext)
            defaults.removeObject(forKey: Self.dataUsernameKey)
            defaults.removeObject(forKey: Self.dataServerKey)
        } catch {
            // Daten bleiben samt Besitzer-Schlüsseln: ein anderer Benutzer löst den Wechsel-Ablauf aus.
            logger.error("Lokaler Store beim Abmelden nicht geleert: \(String(describing: error), privacy: .public)")
            container.mainContext.rollback()
        }
        if let session {
            var cursor = dependencies.makeCursor(session.serverURL, session.userId)
            cursor.lastVersion = 0
        }
        return .loggedOut
    }

    public func scenePhaseChanged(_ phase: ScenePhase) {
        appLock.scenePhaseChanged(phase)
        if phase == .active { scheduler?.appDidBecomeActive() }
    }

    public func pullToRefresh() async {
        await scheduler?.pullToRefresh()
    }

    // MARK: Server-Adresse

    /// Trimmt, ergänzt fehlendes `http://`, verlangt http(s) und einen Host.
    nonisolated public static func normalizeServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    // MARK: Benutzerwechsel

    private func authenticate(username: String, discardPending: Bool,
                              _ action: () async throws -> Void) async throws -> AuthOutcome {
        let switching = wouldSwitch(username: username)
        if switching {
            // Mit noch gültiger Sitzung zuerst senden (sonst hat `logout()` es schon versucht).
            await engine?.syncNow()
            let pending = repository.pendingChangesCount
            if pending > 0 && !discardPending {
                return .needsDiscardConfirmation(pending: pending)
            }
        }
        holdActivation = switching
        if switching { frozenAuthState = auth.state }
        defer {
            holdActivation = false
            frozenAuthState = nil
        }
        try await action()
        // Erst nach erfolgreicher Anmeldung leeren: falsches Passwort verliert keine Daten.
        if switching, case let .loggedIn(session) = auth.state {
            deactivate()
            do {
                try dependencies.wipeStore(container.mainContext)
            } catch {
                logger.error("Lokaler Store nicht geleert: \(String(describing: error), privacy: .public)")
                container.mainContext.rollback()
                // Neue Sitzung nicht auf fremden Daten starten: wieder abmelden.
                await auth.logout()
                throw SwitchError.localDataNotCleared
            }
            defaults.removeObject(forKey: Self.dataUsernameKey)
            defaults.removeObject(forKey: Self.dataServerKey)
            var cursor = dependencies.makeCursor(session.serverURL, session.userId)
            cursor.lastVersion = 0
        }
        holdActivation = false
        frozenAuthState = nil
        authStateChanged()
        return .loggedIn
    }

    /// Anderer Benutzer als zuletzt angemeldet, oder Daten im Store stammen von einem anderen Server.
    private func wouldSwitch(username: String) -> Bool {
        if auth.loginWouldSwitchUser(username) { return true }
        if let owner = defaults.string(forKey: Self.dataUsernameKey),
           Self.normalize(owner) != Self.normalize(username) { return true }
        guard let dataServer = defaults.url(forKey: Self.dataServerKey),
              let target = auth.state.serverURL else { return false }
        return dataServer != target
    }

    nonisolated private static func normalize(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Standard für `Dependencies.wipeStore`: löscht alle Datensätze aller Typen und speichert
    /// (keine Datei-Löschung nötig).
    public static func deleteAllRecords(in context: ModelContext) throws {
        for type in AppSchema.models {
            try deleteAll(type, in: context)
        }
        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }

    // MARK: Sitzung ↔ Sync

    private func observeAuth() {
        withObservationTracking {
            _ = auth.state
        } onChange: { [weak self] in
            // onChange kommt vor der Änderung; den neuen Zustand danach auswerten.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authStateChanged()
                self.observeAuth()
            }
        }
    }

    /// Idempotent: passt Engine/Scheduler an den aktuellen Anmeldezustand an.
    private func authStateChanged() {
        guard case let .loggedIn(session) = auth.state else {
            deactivate()
            return
        }
        let key = SessionKey(serverURL: session.serverURL, userId: session.userId)
        guard !holdActivation, activeSession != key, let client = auth.client else { return }
        deactivate()
        let engine = SyncEngine(context: container.mainContext,
                                transport: dependencies.makeTransport(client),
                                cursor: dependencies.makeCursor(session.serverURL, session.userId))
        let scheduler = dependencies.makeScheduler(engine)
        self.engine = engine
        self.scheduler = scheduler
        activeSession = key
        defaults.set(session.serverURL, forKey: Self.dataServerKey)
        defaults.set(session.username, forKey: Self.dataUsernameKey)
        scheduler.start()
    }

    private func deactivate() {
        scheduler?.stop()
        scheduler = nil
        engine = nil
        activeSession = nil
    }

    // MARK: Zeitlimit

    /// Führt `work` aus, kehrt aber spätestens nach `seconds` zurück (und bricht `work` dann ab).
    static func runBounded(seconds: Double, _ work: @escaping @MainActor () async -> Void) async {
        let race = Race()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            race.continuation = continuation
            race.worker = Task { @MainActor in
                await work()
                race.finish()
            }
            race.timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                race.worker?.cancel()
                race.finish()
            }
        }
    }

    @MainActor
    private final class Race {
        var continuation: CheckedContinuation<Void, Never>?
        var worker: Task<Void, Never>?
        var timer: Task<Void, Never>?

        func finish() {
            timer?.cancel()
            continuation?.resume()
            continuation = nil
        }
    }
}
