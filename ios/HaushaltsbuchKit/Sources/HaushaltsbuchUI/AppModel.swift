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

    public enum AuthOutcome: Equatable, Sendable {
        case loggedIn
        /// Anderer Benutzer/Server, aber ungesendete Änderungen: erst nach Bestätigung verwerfen.
        case needsDiscardConfirmation(pending: Int)
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

        public init(makeTransport: @escaping @MainActor (Client) -> any SyncTransport,
                    makeCursor: @escaping @MainActor (URL, UUID) -> any SyncCursorStore,
                    makeScheduler: @escaping @MainActor (SyncEngine) -> any SyncScheduling) {
            self.makeTransport = makeTransport
            self.makeCursor = makeCursor
            self.makeScheduler = makeScheduler
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

    /// Server, dessen Daten im lokalen Store liegen (für die Wechsel-Erkennung).
    static let dataServerKey = "app.dataServerURL"

    @ObservationIgnored public let container: ModelContainer
    @ObservationIgnored public private(set) var repository: Repository!
    public let auth: AuthService
    public private(set) var engine: SyncEngine?

    @ObservationIgnored private var scheduler: (any SyncScheduling)?
    @ObservationIgnored private var activeSession: SessionKey?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dependencies: Dependencies
    /// Während eines Benutzerwechsels: Sitzung erst nach dem Leeren des Stores aktivieren.
    @ObservationIgnored private var holdActivation = false

    private struct SessionKey: Equatable {
        let serverURL: URL
        let userId: UUID
    }

    public init(container: ModelContainer, auth: AuthService, defaults: UserDefaults = .standard,
                dependencies: Dependencies? = nil) {
        self.container = container
        self.auth = auth
        self.defaults = defaults
        self.dependencies = dependencies ?? .live(defaults: defaults)
        repository = Repository(context: container.mainContext) { [weak self] in
            self?.scheduler?.localChange()
        }
        authStateChanged()
        observeAuth()
    }

    // MARK: Zustand

    public var phase: Phase {
        switch auth.state {
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

    /// Abmelden: vorher noch einmal synchronisieren (best effort), dann Sitzung verwerfen.
    /// Nicht gesendete Änderungen bleiben lokal erhalten.
    public func logout() async {
        await engine?.syncNow()
        deactivate()
        await auth.logout()
    }

    public func scenePhaseChanged(_ phase: ScenePhase) {
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
        defer { holdActivation = false }
        try await action()
        // Erst nach erfolgreicher Anmeldung leeren: falsches Passwort verliert keine Daten.
        if switching, case let .loggedIn(session) = auth.state {
            deactivate()
            wipeStore()
            var cursor = dependencies.makeCursor(session.serverURL, session.userId)
            cursor.lastVersion = 0
        }
        holdActivation = false
        authStateChanged()
        return .loggedIn
    }

    /// Anderer Benutzer als zuletzt angemeldet, oder Daten im Store stammen von einem anderen Server.
    private func wouldSwitch(username: String) -> Bool {
        if auth.loginWouldSwitchUser(username) { return true }
        guard let dataServer = defaults.url(forKey: Self.dataServerKey),
              let target = auth.state.serverURL else { return false }
        return dataServer != target
    }

    /// Löscht alle Datensätze aller Typen (keine Datei-Löschung nötig).
    private func wipeStore() {
        let context = container.mainContext
        do {
            for type in AppSchema.models {
                try deleteAll(type, in: context)
            }
            try context.save()
        } catch {
            logger.error("Lokaler Store nicht geleert: \(String(describing: error), privacy: .public)")
            context.rollback()
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
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
        scheduler.start()
    }

    private func deactivate() {
        scheduler?.stop()
        scheduler = nil
        engine = nil
        activeSession = nil
    }
}
