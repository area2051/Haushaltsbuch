# Haushaltsbuch iOS-App – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Universal-SwiftUI-App (iPhone + iPad), die offline-first mit dem fertigen Server (`server/`) synchronisiert und Buchungen in ~3 Sekunden erfassen lässt.

**Architecture:** Dünnes App-Target (XcodeGen, `ios/project.yml`) über einem lokalen Swift-Package `HaushaltsbuchKit` mit vier Modulen: `HaushaltsbuchAPI` (generiert aus `server/openapi.json`), `HaushaltsbuchCore` (reine Logik), `HaushaltsbuchData` (SwiftData, Keychain, Auth, Sync) und `HaushaltsbuchUI` (SwiftUI). Views lesen nur aus SwiftData und schreiben nur über das `Repository`; die `SyncEngine` gleicht über `POST /sync` ab.

**Tech Stack:** Xcode 27.2, Swift 6 (Language Mode 6), iOS 18 Deployment Target, SwiftUI, SwiftData, Swift Charts, Swift Testing, swift-openapi-generator / -runtime / -urlsession (1.x), LocalAuthentication, Network (`NWPathMonitor`), XcodeGen (Homebrew).

**Spec:** `docs/superpowers/specs/2026-11-01-haushaltsbuch-design.md` (§2 App, §4 Client-Teil, §7 komplett, §8). Server-Vertrag: `server/openapi.json`.

## Global Constraints

- Alles unter `ios/`. Bundle-ID `de.haushaltsbuch.app` (in `project.yml`, `DEVELOPMENT_TEAM` leer → Simulator-Builds ohne Signing).
- iOS 18.0 Deployment Target, `TARGETED_DEVICE_FAMILY = 1,2`, Swift 6 Language Mode, strikte Concurrency.
- Builds/Tests immer über `xcodebuild` gegen den Simulator `iPhone 17` (iOS 26.5); iPad-Prüfung auf `iPad Pro 11-inch (M5)`. Skript `ios/scripts/test.sh` ist der einzige Testeinstieg.
- Sprache der Oberfläche: Deutsch, fest im Code (keine Lokalisierungsdateien). Formatierung mit `Locale(identifier: "de_DE")`, Währung EUR.
- Beträge: `Int` Cent, > 0. Ziffernblock erlaubt max. 9 Ziffern (999.999.999 Cent < 2147483647).
- Kalenderdaten: `CalendarDay` (Jahr/Monat/Tag) bzw. String `YYYY-MM-DD`; nie `Date` mit Uhrzeit speichern. „Heute“ = `Calendar.current` in der Gerätezeitzone.
- IDs: lokal immer `UUID` (Swift-Typ). Server-Strings über `UUID(uuidString:)` parsen (case-insensitiv); beim Senden `uuidString.lowercased()`.
- Sync: max. 500 Datensätze pro `POST /sync`; weitere Dirty-Datensätze in Folgerequests (Server-Limit 10 MiB, `payload_too_large`).
- Sync-Auslöser: App-Start, Vordergrund, 2 s nach letzter lokaler Änderung, Netz wieder da, Pull-to-Refresh. Backoff nach Fehlern: 5 s, verdoppelt, max. 300 s.
- Fehler des Servers kommen als `{ "error": { "code", "message" } }`; Codes aus dem Server verwenden (`invalid_credentials`, `too_many_attempts`, `invalid_refresh_token`, `setup_already_done`, `username_taken`, `last_admin`, `cannot_delete_self`, `payload_too_large`, …).
- Passwortänderung über `PATCH /me` ist **nicht** Teil der v1-Oberfläche (Spec §7 listet sie nicht). Falls später ergänzt: `keepRefreshToken` mitsenden.
- Commit-Messages enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Bearbeitung während eines laufenden Syncs** → die lokale Änderung geht nicht verloren: der Datensatz bleibt dirty und wird im nächsten Sync gesendet, die Server-Antwort überschreibt ihn nicht. Test in Task 8.
2. **Server nicht erreichbar (VPN aus)** → App arbeitet normal, Status zeigt „Nicht mit NAS verbunden – N Änderungen ausstehend“, Wiederholung mit Backoff, keine Datenverluste. Test in Task 8.
3. **Access-Token läuft mitten in der Nutzung ab** → genau ein Refresh, Request wird wiederholt; parallele Requests lösen nur einen Refresh aus; scheitert der Refresh, Wechsel zum Login ohne lokale Daten zu löschen. Test in Task 7.
4. **Optionale Felder (`note`, `recurringRuleId`, `endDate`) sind `nil`** → der generierte Client sendet sie als `null` (Server verlangt die Schlüssel). Test in Task 2.
5. **Nach Backup-Restore (`fullResync: true`)** → lokale, nicht-dirty Datensätze, die nicht in der Antwort stehen, verschwinden; dirty Datensätze werden vorher gesendet und bleiben. Test in Task 8.

---

## File Structure

```
ios/
  project.yml                       XcodeGen: App-Target "Haushaltsbuch" + lokales Package
  Haushaltsbuch/                    App-Target (nur Einstieg + Ressourcen)
    HaushaltsbuchApp.swift          @main, ModelContainer, AppModel, RootView
    Info.plist                      ATS, Local Network, Face ID
    Assets.xcassets
  HaushaltsbuchKit/
    Package.swift
    Sources/
      HaushaltsbuchAPI/             openapi.json (Kopie), openapi-generator-config.yaml
      HaushaltsbuchCore/            CalendarDay, Money, AmountInput, Analytics, CSVExport
      HaushaltsbuchData/            Models/, Repository, Keychain, AuthService, AuthMiddleware,
                                    SyncEngine, SyncMapping, SyncScheduler, Session
      HaushaltsbuchUI/              Onboarding/, QuickEntry/, Transactions/, Overview/,
                                    Budgets/, More/, Components/, RootView, AppModel
    Tests/
      HaushaltsbuchAPITests/  HaushaltsbuchCoreTests/  HaushaltsbuchDataTests/  HaushaltsbuchUITests/
  scripts/
    sync-openapi.sh                 kopiert server/openapi.json → Sources/HaushaltsbuchAPI/openapi.json
    test.sh                         xcodebuild test für das Package auf dem iPhone-17-Simulator
docs/ios.md                         Build, Installation auf Geräten, Server-Adresse
```

---

### Task 1: Toolchain, Projektgerüst, Testeinstieg

**Files:**
- Create: `ios/project.yml`, `ios/Haushaltsbuch/HaushaltsbuchApp.swift`, `ios/Haushaltsbuch/Info.plist`, `ios/Haushaltsbuch/Assets.xcassets`, `ios/HaushaltsbuchKit/Package.swift`, je ein Platzhalter-Source + `PlaceholderTests.swift` pro Modul, `ios/scripts/test.sh`
- Modify: `.gitignore` (`ios/*.xcodeproj`, `ios/HaushaltsbuchKit/.build/`, `ios/build/`)

**Interfaces:**
- Produces: Package-Produkte `HaushaltsbuchAPI`, `HaushaltsbuchCore`, `HaushaltsbuchData`, `HaushaltsbuchUI` (Abhängigkeiten: UI → Data → Core, Data → API). Package-Plattform `.iOS(.v18)`; Swift-Tools-Version 6.0.
- `ios/scripts/test.sh [Filter]` – führt `xcodebuild test -scheme HaushaltsbuchKit-Package -destination 'platform=iOS Simulator,name=iPhone 17'` im Package-Verzeichnis aus (optional `-only-testing:`), Exit-Code = Testergebnis.
- Die `.xcodeproj` ist generiert (`xcodegen generate` in `ios/`) und nicht eingecheckt.

- [ ] **Step 1: Voraussetzungen prüfen** – `xcodebuild -version` zeigt Xcode 27.2 (User hat `sudo xcode-select -s /Applications/Xcode.app` ausgeführt; falls nicht: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in `test.sh`). `brew install xcodegen`.
- [ ] **Step 2: Package + Platzhalter-Test** – je Modul ein `@Test func moduleLoads()` mit `#expect(true)` ist hier zulässig, da der Zweck die Testinfrastruktur ist.
- [ ] **Step 3: `ios/scripts/test.sh`** → PASS für alle vier Testtargets.
- [ ] **Step 4: `project.yml` + `xcodegen generate`**, App zeigt Platzhalter „Haushaltsbuch“. Prüfen: `xcodebuild build -project ios/Haushaltsbuch.xcodeproj -scheme Haushaltsbuch -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED; App im Simulator starten, Screenshot zeigt den Text.
- [ ] **Step 5: Info.plist** – `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` (Server ist HTTP im LAN/VPN, Hostname beliebig), `NSLocalNetworkUsageDescription` = „Das Haushaltsbuch verbindet sich mit deinem Server im Heimnetz.“, `NSFaceIDUsageDescription` = „Face ID schützt dein Haushaltsbuch.“
- [ ] **Step 6: Commit** – `feat(ios): project skeleton with XcodeGen and local package`

---

### Task 2: Generierter API-Client

**Files:**
- Create: `ios/scripts/sync-openapi.sh`, `ios/HaushaltsbuchKit/Sources/HaushaltsbuchAPI/openapi.json` (Kopie), `.../openapi-generator-config.yaml`, `.../Client+Make.swift`
- Modify: `ios/HaushaltsbuchKit/Package.swift` (Abhängigkeiten swift-openapi-generator Plugin, -runtime, -urlsession)
- Test: `ios/HaushaltsbuchKit/Tests/HaushaltsbuchAPITests/CodingTests.swift`
- Ggf. Modify (nur wenn Step 3 scheitert): `server/src/sync/schemas.ts` + `server/openapi.json`

**Interfaces:**
- Produces: generierte Typen `Components.Schemas.*` (Namen wie in `openapi.json`, z. B. `TransactionRecord`, `SyncResponse`) und `Client` mit Methoden je operationId (`getHealth`, `setup`, `login`, `refresh`, `logout`, `getMe`, `updateMe`, `listUsers`, `createUser`, `updateUser`, `sync`). Generator-Config: `generate: [types, client]`, `accessModifier: public`.
- `public func makeClient(serverURL: URL, middlewares: [any ClientMiddleware]) -> Client` (URLSessionTransport).
- `sync-openapi.sh` kopiert und bricht mit Exit 1 ab, wenn `--check` übergeben wird und die Kopie veraltet ist.

- [ ] **Step 1: Failing Tests**

```swift
@Test func decodesSyncResponseWithLowercaseIdsAndNulls() throws   // Fixture-JSON mit note:null, recurringRuleId:null → decodiert
@Test func ignoresUnknownResponseFields() throws                  // Fixture mit zusätzlichem Feld "futureField" → decodiert ohne Fehler
@Test func encodesNilOptionalsAsExplicitNull() throws              // TransactionRecord(note: nil, recurringRuleId: nil) → JSON enthält "note":null und "recurringRuleId":null  (Review Focus 4)
@Test func encodesRecurringRuleNilEndDateAsNull() throws
```
- [ ] **Step 2: FAIL bestätigen** (`ios/scripts/test.sh HaushaltsbuchAPITests`).
- [ ] **Step 3: Generator einrichten, bauen, Tests grün machen.** Lässt der Generator `nil` weg statt `null` zu senden (Test 3/4 rot), dann **serverseitig** nachgeben: Eingabe-Schemas für `note`, `recurringRuleId`, `endDate` akzeptieren fehlende Schlüssel als `null` (`.nullish().transform(v => v ?? null)` o. ä.), Server-Tests + `npm run openapi` + `npm test` grün, Kopie neu synchronisieren, und Test 3/4 so umschreiben, dass sie „fehlender Schlüssel oder null“ akzeptieren. Entscheidung im Report festhalten.
- [ ] **Step 4: `ios/scripts/test.sh HaushaltsbuchAPITests`** → PASS; `ios/scripts/sync-openapi.sh --check` → Exit 0.
- [ ] **Step 5: Commit** – `feat(ios): generated OpenAPI client`

---

### Task 3: Core-Werte – CalendarDay, Money, AmountInput

**Files:**
- Create: `Sources/HaushaltsbuchCore/CalendarDay.swift`, `Money.swift`, `AmountInput.swift`
- Test: `Tests/HaushaltsbuchCoreTests/CalendarDayTests.swift`, `MoneyTests.swift`, `AmountInputTests.swift`

**Interfaces:**
- `public struct CalendarDay: Hashable, Comparable, Sendable, Codable { year, month, day: Int; init?(string: String); var string: String; static func today(calendar: Calendar = .current) -> CalendarDay; var monthKey: MonthKey }`
- `public struct MonthKey: Hashable, Comparable, Sendable { year, month: Int; func adding(months: Int) -> MonthKey; func contains(_ d: CalendarDay) -> Bool; var title: String /* "November 2026" */ }`
- `public enum Money { static func format(cents: Int) -> String /* "12,50 €" */; static func formatSigned(cents: Int, kind: Kind) -> String }`; `public enum Kind: String, Sendable { case income, expense }`
- `public struct AmountInput: Equatable, Sendable { private(set) var cents: Int; mutating func append(digit: Int); mutating func deleteLast(); mutating func clear(); var isValid: Bool /* cents > 0 */; var display: String }`

- [ ] **Step 1: Failing Tests**

```swift
@Test func amountInputFromRight() { var a = AmountInput(); [1,2,5,0].forEach { a.append(digit: $0) }; #expect(a.cents == 1250); #expect(a.display == "12,50 €") }
@Test func amountInputIgnoresTenthDigit() { /* 9 Ziffern 9 → 999_999_999; 10. Ziffer ignoriert */ }
@Test func amountInputIgnoresLeadingZero() { /* append 0 auf leerem Input → cents 0, isValid false */ }
@Test func deleteLastRemovesRightmostDigit() { /* 1250 → 125 */ }
@Test func moneyFormatsGerman() { #expect(Money.format(cents: 123456) == "1.234,56 €") }
@Test func calendarDayParsesAndRejects() { /* "2026-02-29" nil, "2028-02-29" ok, "2026-1-5" nil */ }
@Test func monthKeyTitleGerman() { #expect(MonthKey(year: 2026, month: 3).title == "März 2026") }
@Test func monthKeyAddingAcrossYear() { /* 2026-12 + 1 = 2027-01 */ }
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** (Formatter mit `de_DE`; Leerzeichen vor „€“ ggf. geschütztes Leerzeichen – Test vergleicht nach Normalisierung von `\u{00A0}` zu Leerzeichen) – **Step 4: PASS** – **Step 5: Commit** `feat(ios): calendar day, money and amount input`

---

### Task 4: Core-Auswertungen – Summen, Budgets, Kategorie-Ranking

**Files:**
- Create: `Sources/HaushaltsbuchCore/Analytics.swift`
- Test: `Tests/HaushaltsbuchCoreTests/AnalyticsTests.swift`

**Interfaces:**
- Consumes: `CalendarDay`, `MonthKey`, `Kind` (Task 3).
- Eingabewerte (Core kennt SwiftData nicht): `public struct TxValue: Sendable { id: UUID; amountCents: Int; kind: Kind; categoryId: UUID; day: CalendarDay; paidBy: UUID; note: String? }`, `public struct CategoryValue: Sendable { id: UUID; name: String; icon: String; color: String; kind: Kind; sortOrder: Int; archived: Bool }`, `public struct BudgetValue: Sendable { categoryId: UUID; monthlyLimitCents: Int }`
- `public struct MonthSummary: Equatable { incomeCents, expenseCents: Int; var balanceCents: Int }`
- `public enum Analytics`:
  - `static func summary(_ txs: [TxValue], month: MonthKey) -> MonthSummary`
  - `static func expensesByCategory(_ txs: [TxValue], month: MonthKey) -> [(categoryId: UUID, cents: Int)]` – absteigend nach Betrag
  - `static func expensesByPerson(_ txs: [TxValue], month: MonthKey) -> [(userId: UUID, cents: Int)]`
  - `static func budgetProgress(_ budgets: [BudgetValue], txs: [TxValue], month: MonthKey) -> [BudgetProgress]`; `public struct BudgetProgress { categoryId: UUID; spentCents, limitCents: Int; var ratio: Double; var level: Level /* .ok < 0.8, .warning >= 0.8, .exceeded >= 1.0 */ }`
  - `static func rankCategories(_ cats: [CategoryValue], txs: [TxValue], kind: Kind, today: CalendarDay) -> [CategoryValue]` – nur nicht archivierte der Art, sortiert nach Anzahl Buchungen der letzten 90 Tage (inkl. heute) absteigend, Gleichstand nach `sortOrder`.

- [ ] **Step 1: Failing Tests**

```swift
@Test func summaryOnlyCountsMonth()
@Test func expensesByCategoryIgnoresIncomeAndSortsDescending()
@Test func expensesByPersonGroupsByPaidBy()
@Test func budgetLevelsAtThresholds()        // 79 % ok, 80 % warning, 100 % exceeded
@Test func rankCategoriesUsesLast90DaysThenSortOrder()  // Buchung vor 91 Tagen zählt nicht
@Test func rankCategoriesExcludesArchivedAndOtherKind()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(ios): analytics for summaries, budgets and category ranking`

---

### Task 5: CSV-Export

**Files:**
- Create: `Sources/HaushaltsbuchCore/CSVExport.swift`
- Test: `Tests/HaushaltsbuchCoreTests/CSVExportTests.swift`

**Interfaces:**
- Consumes: `TxValue`, `CategoryValue` (Task 4), `Money`, `CalendarDay`.
- `public enum CSVExport { static func make(_ txs: [TxValue], categories: [UUID: CategoryValue], members: [UUID: String], from: CalendarDay, to: CalendarDay) -> Data }` – UTF-8 **mit BOM**, Trennzeichen `;`, Zeilenende `\r\n`, Kopfzeile `Datum;Art;Kategorie;Betrag;Notiz;Bezahlt von`, Datum `TT.MM.JJJJ`, Art `Ausgabe`/`Einnahme`, Betrag mit Dezimalkomma ohne Währungszeichen und ohne Tausenderpunkt (`1234,56`), sortiert nach Datum aufsteigend; Felder mit `;`, `"` oder Zeilenumbruch in `"` eingeschlossen, `"` verdoppelt; unbekannte Kategorie/Person → leeres Feld.
- `public static func fileName(from: CalendarDay, to: CalendarDay) -> String` → `Haushaltsbuch_2026-11-01_2026-11-30.csv`

- [ ] **Step 1: Failing Tests**

```swift
@Test func startsWithBOMAndHeader()
@Test func formatsRowGerman()                 // 12,50 / 01.11.2026 / Ausgabe
@Test func escapesSemicolonQuoteAndNewline()
@Test func filtersRangeInclusive()
@Test func fileNameUsesRange()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(ios): CSV export`

---

### Task 6: SwiftData-Modelle und Repository

**Files:**
- Create: `Sources/HaushaltsbuchData/Models/{CategoryEntity,TransactionEntity,BudgetEntity,RecurringRuleEntity,MemberEntity}.swift`, `Sources/HaushaltsbuchData/SyncTracked.swift`, `Sources/HaushaltsbuchData/Repository.swift`, `Sources/HaushaltsbuchData/ModelContainer+App.swift`
- Test: `Tests/HaushaltsbuchDataTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: Core-Werte (Tasks 3–4).
- Jede Sync-Entity (`@Model final class`): `@Attribute(.unique) var id: UUID`, `var version: Int?` (nil = nie synchronisiert), `var deleted: Bool`, `var isDirty: Bool`, `var dirtyGeneration: Int`, `var rejectionReason: String?` + Fachfelder wie Spec §3 (Tage als `String` `YYYY-MM-DD`: `day`, `startDate`, `endDate?`, `nextDueDate?`; `kind`/`frequency` als `String` rawValue). `MemberEntity`: `id, username, displayName, isAdmin, deleted, version` (nie dirty).
- `protocol SyncTracked: AnyObject { var id: UUID; var version: Int?; var deleted: Bool; var isDirty: Bool; var dirtyGeneration: Int; var rejectionReason: String? }`; `extension SyncTracked { func markDirty() /* isDirty = true, dirtyGeneration += 1, rejectionReason = nil */ }`
- Jede Entity hat `var value: <Core>Value` (Mapping zu `TxValue` usw.).
- `public static func makeAppContainer(inMemory: Bool = false) throws -> ModelContainer`
- `@MainActor public final class Repository` (init mit `ModelContext`, `onChange: @MainActor () -> Void` – ruft der Sync-Scheduler für den 2-s-Debounce ab):
  - `func addTransaction(amountCents: Int, kind: Kind, categoryId: UUID, day: CalendarDay, paidBy: UUID, note: String?) throws -> TransactionEntity`
  - `func update(_ tx: TransactionEntity, amountCents:kind:categoryId:day:paidBy:note:) throws`
  - `func delete(_ tx: TransactionEntity) throws` – Soft-Delete (`deleted = true`, dirty)
  - `func saveCategory(_ draft: CategoryDraft) throws -> CategoryEntity` (anlegen/ändern), `func removeCategory(_ c: CategoryEntity) throws` – hat die Kategorie nicht gelöschte Buchungen oder Regeln → `archived = true`, sonst `deleted = true`; `func moveCategories(_ ordered: [CategoryEntity]) throws` (sortOrder neu)
  - `func setBudget(categoryId: UUID, monthlyLimitCents: Int?) throws` – `nil` löscht das aktive Budget (soft)
  - `func saveRule(_ draft: RuleDraft) throws -> RecurringRuleEntity`, `func deleteRule(_ r: RecurringRuleEntity) throws`
  - `func discardRejected(_ e: any SyncTracked) throws` – nie synchronisiert → hart löschen; sonst `rejectionReason = nil`, `isDirty = false` und Neuabruf anfordern (`onRefetchNeeded`: Sync-Cursor auf 0, Sync über den Scheduler anstoßen). Ein normaler Pull bringt den Server-Stand *nicht* zurück: der Server liefert nur Zeilen mit `version > lastVersion`, und die abgelehnte Zeile hat sich dort nicht geändert. Erst der Abruf ab Version 0 überschreibt die (nicht mehr dirty) lokale Kopie mit dem Server-Stand. Die Engine setzt den Cursor ebenfalls auf 0, sobald eine Antwort einen schon synchronisierten Datensatz ablehnt; ein abgelehntes Löschen wird wieder sichtbar (`deleted = false`), und abgelehnte Zeilen werden von Pulls nicht überschrieben, bis sie bearbeitet oder verworfen sind.
  - `func pendingChanges() throws -> PendingChanges` (dirty und abgelehnte über alle Typen; wirft bei Lesefehlern – vor dem Löschen nie als „nichts ausstehend“ werten)
  - Alle Schreibmethoden setzen `markDirty()`, speichern den Context und rufen `onChange()`.

- [ ] **Step 1: Failing Tests** (In-Memory-Container)

```swift
@Test func addTransactionIsDirtyWithNilVersion()
@Test func updateBumpsDirtyGenerationAndClearsRejection()
@Test func deleteIsSoftAndDirty()
@Test func removeCategoryWithTransactionsArchives()
@Test func removeCategoryWithoutUsageDeletes()
@Test func setBudgetNilSoftDeletesActiveBudget()
@Test func discardRejectedNeverSyncedHardDeletes()
@Test func pendingChangesCountCountsAllTypes()
@Test func writesCallOnChange()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(ios): SwiftData models and repository`

---

### Task 7: Server-Konfiguration, Keychain, Auth und Token-Middleware

**Files:**
- Create: `Sources/HaushaltsbuchData/Keychain.swift`, `Session.swift`, `AuthService.swift`, `AuthMiddleware.swift`, `APIError.swift`
- Test: `Tests/HaushaltsbuchDataTests/AuthMiddlewareTests.swift`, `AuthServiceTests.swift`

**Interfaces:**
- Consumes: `Client`, `makeClient` (Task 2).
- `public protocol TokenStore: Sendable { func load() -> StoredSession?; func save(_ s: StoredSession?) }`; `public struct StoredSession: Codable, Sendable { serverURL: URL; accessToken: String; refreshToken: String; userId: UUID; username: String; isAdmin: Bool }`; `KeychainTokenStore` (Service `de.haushaltsbuch.app.session`, `kSecAttrAccessibleAfterFirstUnlock`), `InMemoryTokenStore` für Tests.
- `public enum APIError: Error, Equatable { case server(code: String, message: String), unreachable, unauthorized, unexpected(String) }` + `var germanMessage: String` (z. B. `invalid_credentials` → „Benutzername oder Passwort falsch.“, `too_many_attempts` → „Zu viele Versuche – bitte eine Minute warten.“, `unreachable` → „Server nicht erreichbar. Bist du im Heimnetz oder per VPN verbunden?“)
- `public actor TokenRefresher` – single-flight: `func validAccessToken() async throws -> String`, `func refreshAfterUnauthorized(failedToken: String) async throws -> String` (startet nur einen Refresh, auch bei parallelen Aufrufern; ist das Token schon erneuert, wird das neue zurückgegeben); bei `invalid_refresh_token` → `TokenStore.save(nil)` und `APIError.unauthorized`.
- `public struct AuthMiddleware: ClientMiddleware` – setzt `Authorization: Bearer …` außer für `getHealth`, `setup`, `login`, `refresh`; bei 401 einmal `refreshAfterUnauthorized` und Wiederholung.
- `@MainActor public final class AuthService: ObservableObject` – `@Published state: AuthState` (`.needsServer`, `.needsSetup(URL)`, `.needsLogin(URL)`, `.loggedIn(StoredSession)`); `func connect(to url: URL) async throws` (GET /health), `func setup(username:displayName:password:) async throws`, `func login(username:password:) async throws`, `func logout() async`, `var client: Client?`. Login speichert `lastUsername` in UserDefaults; `func loginWouldSwitchUser(_ username: String) -> Bool`.

- [ ] **Step 1: Failing Tests** (Fake-`ClientTransport`, der Antworten aus einer Queue liefert und Requests mitschneidet)

```swift
@Test func addsBearerTokenToProtectedRoutes()
@Test func doesNotAddTokenToLogin()
@Test func refreshesOnceOn401AndRetries()                      // Review Focus 3
@Test func parallelRequestsTriggerSingleRefresh()              // 3 gleichzeitige 401 → genau 1 POST /auth/refresh
@Test func failedRefreshClearsSessionAndThrowsUnauthorized()
@Test func connectReportsSetupRequired()
@Test func loginMapsInvalidCredentials()
@Test func unreachableServerMapsToUnreachable()                // URLError.cannotConnectToHost → .unreachable
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(ios): auth service, keychain session and token middleware`

---

### Task 8: SyncEngine und Scheduler

**Files:**
- Create: `Sources/HaushaltsbuchData/SyncMapping.swift`, `SyncEngine.swift`, `SyncScheduler.swift`
- Test: `Tests/HaushaltsbuchDataTests/SyncEngineTests.swift`, `SyncSchedulerTests.swift`

**Interfaces:**
- Consumes: Entities/Repository (Task 6), generierte Typen (Task 2), `APIError` (Task 7).
- `public protocol SyncTransport: Sendable { func sync(_ request: Components.Schemas.SyncRequest) async throws -> Components.Schemas.SyncResponse }`; `ClientSyncTransport(client:)` als Implementierung.
- `public protocol SyncCursorStore { var lastVersion: Int { get set } }` – `UserDefaultsCursorStore(key:)`, Schlüssel enthält Server-URL + userId.
- `@MainActor public final class SyncEngine: ObservableObject`:
  - `@Published private(set) var status: SyncStatus` – `.idle`, `.syncing`, `.offline(pending: Int)`, `.error(String, pending: Int)`, `.upToDate(Date)`
  - `func syncNow() async` – Ablauf:
    1. Snapshot aller dirty Datensätze (Reihenfolge Kategorien → Regeln → Buchungen → Budgets), je Datensatz `id → dirtyGeneration`; in Paketen à max. 500.
    2. `POST /sync` mit `lastVersion` und dem Paket (IDs `lowercased()`).
    3. Antwort anwenden: je Datensatz per `UUID(uuidString:)` suchen; ist er lokal dirty **und** `dirtyGeneration` ≠ Snapshot (oder nicht im Snapshot) → nicht überschreiben; sonst Felder + `version` übernehmen, `isDirty = false`. Unbekannte → anlegen. `users` → `MemberEntity` upserten.
    4. `rejected`: passenden Datensatz `rejectionReason = reason`, `isDirty = false` (kein Endlos-Resend).
    5. `fullResync == true`: alle lokalen Datensätze, die nicht dirty sind und nicht in der Antwort vorkommen, hart löschen.
    6. `lastVersion = currentVersion`; weitere Pakete bis keine dirty mehr (gleiches Protokoll); Context speichern.
    7. Fehler `unreachable` → `.offline(pending:)`; `unauthorized` → Sync stoppt (AuthService zeigt Login); sonstige → `.error`.
- `@MainActor public final class SyncScheduler` – `init(engine:, sleeper: Sleeper, pathMonitor: NetworkStatusProviding)`; `func start()`, `func appDidBecomeActive()`, `func localChange()` (Debounce 2 s), `func pullToRefresh() async`; Backoff 5 s · 2ⁿ, max 300 s, Reset bei Erfolg; reagiert auf „Netz wieder da“. `protocol Sleeper { func sleep(seconds: Double) async throws }` für Tests.

- [ ] **Step 1: Failing Tests** (In-Memory-Container + Fake-Transport)

```swift
@Test func pushesDirtyAndClearsDirtyFromResponse()
@Test func editDuringInFlightSyncStaysDirty()                  // Review Focus 1: Fake-Transport ändert den Datensatz via Repository, bevor er antwortet
@Test func appliesServerChangesAndUpsertsMembers()
@Test func uppercaseLocalIdMatchesLowercaseServerId()
@Test func rejectedRecordIsMarkedAndNotResent()
@Test func fullResyncRemovesUnknownCleanRecordsKeepsDirty()    // Review Focus 5
@Test func storesCurrentVersionAsCursor()
@Test func splitsPushIntoBatchesOf500()
@Test func unreachableKeepsDataAndReportsPending()             // Review Focus 2
@Test func schedulerDebouncesLocalChanges()
@Test func schedulerBacksOffUpTo300Seconds()
@Test func schedulerSyncsWhenNetworkReturns()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(ios): sync engine and scheduler`

---

### Task 9: App-Shell, Onboarding, Navigation

**Files:**
- Create: `Sources/HaushaltsbuchUI/AppModel.swift`, `RootView.swift`, `Onboarding/{ServerView,SetupView,LoginView}.swift`, `MainTabView.swift`, `MainSplitView.swift`, `Components/SyncStatusBanner.swift`
- Modify: `ios/Haushaltsbuch/HaushaltsbuchApp.swift`
- Test: `Tests/HaushaltsbuchUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: `AuthService` (7), `SyncEngine`/`SyncScheduler` (8), `Repository` (6).
- `@MainActor public final class AppModel: ObservableObject` – besitzt Container, Repository, AuthService, SyncEngine, Scheduler; `var phase: Phase` (`.onboarding`, `.locked`, `.ready`); startet Scheduler nach Login; reagiert auf `scenePhase` (`.active` → `appDidBecomeActive`); bei `AuthState.needsLogin` nach Token-Ablauf bleiben lokale Daten erhalten.
- Login eines **anderen** Benutzers (`loginWouldSwitchUser`): vorher Sync versuchen; bleiben ausstehende Änderungen, Bestätigungsdialog „N ungesendete Änderungen verwerfen?“; dann lokalen Store leeren und Cursor zurücksetzen.
- `RootView`: `horizontalSizeClass == .compact` → `MainTabView` (Tabs „Übersicht“, „Buchungen“, „+“, „Budgets“, „Mehr“; Auswahl von „+“ öffnet das Erfassungs-Sheet und kehrt zum vorherigen Tab zurück), sonst `MainSplitView` (`NavigationSplitView`, Toolbar-Button „+“ und `.keyboardShortcut("n")`).
- `SyncStatusBanner`: nur sichtbar bei `.offline`/`.error`, Text „Nicht mit NAS verbunden – N Änderungen ausstehend“.
- Platzhalter-Views für Übersicht/Buchungen/Budgets/Mehr/Erfassung (werden in Tasks 10–13 ersetzt).

- [ ] **Step 1: Failing Tests** – `AppModel` mit Fakes: `@Test func startsInOnboardingWithoutSession()`, `@Test func readyAfterLoginAndStartsScheduler()`, `@Test func expiredSessionKeepsLocalData()`, `@Test func switchingUserWithPendingChangesRequiresConfirmation()`.
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Live-Prüfung** – lokalen Server starten (`docker compose up -d` im Repo-Root mit lokaler `.env`, `DATA_DIR`/`BACKUP_DIR` außerhalb von OneDrive, z. B. `~/haushaltsbuch-dev/…`), App im Simulator: Server-URL `http://localhost:3000` → Setup-Screen → Admin anlegen → Hauptansicht mit Tabs; auf dem iPad-Simulator Seitenleiste. Screenshots ablegen und im Report referenzieren. Danach `docker compose down`.
- [ ] **Step 6: Commit** – `feat(ios): app shell, onboarding and navigation`

---

### Task 10: Schnellerfassung

**Files:**
- Create: `Sources/HaushaltsbuchUI/QuickEntry/{QuickEntryModel,QuickEntryView,KeypadView,CategoryGridView}.swift`
- Test: `Tests/HaushaltsbuchUITests/QuickEntryModelTests.swift`

**Interfaces:**
- Consumes: `AmountInput` (3), `Analytics.rankCategories` (4), `Repository.addTransaction` (6), `MemberEntity`.
- `@MainActor final class QuickEntryModel: ObservableObject` – `amount: AmountInput`, `kind: Kind = .expense`, `day: CalendarDay = .today()`, `paidBy: UUID` (= eingeloggter Benutzer), `note: String`, `detailsExpanded = false`, `var categories: [CategoryValue]` (gerankt, wechselt mit `kind`), `var canSave: Bool { amount.isValid }`, `func save(category: UUID) throws` (legt Buchung an; leere Notiz → `nil`).
- View: Betragsanzeige groß oben, Ziffernblock (1–9, „00“ nicht vorhanden, 0, Löschen), darunter Kategorie-Raster (deaktiviert solange `!canSave`), aufklappbarer Bereich „Details“ (Segment Ausgabe/Einnahme, DatePicker, Picker „Bezahlt von“ mit nicht gelöschten Mitgliedern, Notizfeld). Tipp auf Kategorie → `save`, `UINotificationFeedbackGenerator().notificationOccurred(.success)`, Sheet schließt. VoiceOver-Labels für Tasten („Ziffer 1“, „Löschen“) und Kategorien (Name).

- [ ] **Step 1: Failing Tests**

```swift
@Test func cannotSaveWithoutAmount()
@Test func saveCreatesExpenseTodayPaidByMe()
@Test func switchingToIncomeShowsIncomeCategories()
@Test func emptyNoteSavedAsNil()
@Test func categoriesRankedByRecentUse()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Live-Prüfung im Simulator** – Betrag 12,50 tippen, „Lebensmittel“ tippen → Sheet schließt, Buchung erscheint nach Sync auf dem Server (`POST /sync` per curl mit lastVersion 0 zeigt sie). Screenshot.
- [ ] **Step 6: Commit** – `feat(ios): quick entry`

---

### Task 11: Buchungsliste und Bearbeiten

**Files:**
- Create: `Sources/HaushaltsbuchUI/Transactions/{TransactionListModel,TransactionListView,TransactionRow,TransactionEditView}.swift`
- Test: `Tests/HaushaltsbuchUITests/TransactionListModelTests.swift`

**Interfaces:**
- Consumes: Entities, `Repository.update/delete/discardRejected` (6), `Money` (3), `SyncScheduler.pullToRefresh` (8).
- `struct TransactionFilter: Equatable { var search = ""; var categoryId: UUID?; var paidBy: UUID?; var kind: Kind? }`
- `enum TransactionListModel { static func sections(_ txs: [TxValue], filter: TransactionFilter, categories: [UUID: CategoryValue]) -> [(day: CalendarDay, items: [TxValue])] }` – absteigend nach Tag, Suche case-insensitiv in Notiz **und** Kategoriename, gelöschte ausgeschlossen.
- Liste: Abschnitts-Header „Montag, 2. November“ (de_DE), Zeile mit Kategorie-Symbol/Farbe, Notiz oder Kategoriename, Betrag (Ausgaben ohne Vorzeichen, Einnahmen mit „+“ grün), Hinweis-Symbol bei `rejectionReason` („Konnte nicht gespeichert werden“ mit Aktionen „Bearbeiten“/„Verwerfen“). Swipe → Löschen. Tippen → `TransactionEditView` (alle Felder, gleiche Bausteine wie die Erfassung). `.refreshable` → `pullToRefresh`. `.searchable`, Filter-Menü in der Toolbar.

- [ ] **Step 1: Failing Tests**

```swift
@Test func groupsByDayDescending()
@Test func searchMatchesNoteAndCategoryName()
@Test func filtersByPersonCategoryAndKind()
@Test func excludesDeleted()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Live-Prüfung** – Buchung bearbeiten und per Swipe löschen, Pull-to-Refresh. Screenshot.
- [ ] **Step 6: Commit** – `feat(ios): transaction list and editing`

---

### Task 12: Übersicht und Budgets

**Files:**
- Create: `Sources/HaushaltsbuchUI/Overview/{OverviewView,MonthPicker,CategoryDonutChart,PersonBarChart}.swift`, `Sources/HaushaltsbuchUI/Budgets/{BudgetsView,BudgetEditView}.swift`
- Test: `Tests/HaushaltsbuchUITests/OverviewModelTests.swift`

**Interfaces:**
- Consumes: `Analytics` (4), `Repository.setBudget` (6), `MonthKey` (3).
- `struct OverviewModel { static func make(txs:, categories:, members:, budgets:, month: MonthKey) -> OverviewData }`; `OverviewData { summary: MonthSummary; byCategory: [ChartSlice]; byPerson: [ChartBar]; warnings: [BudgetProgress] /* nur .warning/.exceeded */; recent: [TxValue] /* letzte 5 im Monat */ }`
- Übersicht: Monatswähler (Pfeile + horizontales Wischen), Saldo mit Einnahmen/Ausgaben, Donut (`SectorMark`, Kategorie-Farben), Balken nach Person (`BarMark`), Budget-Warnungen (gelb ab 80 %, rot ab 100 %), letzte 5 Buchungen. Auf dem iPad (regular width) Diagramme nebeneinander (`ViewThatFits`/`Grid`). Leerer Monat → Hinweis „Noch keine Buchungen in diesem Monat“.
- Budgets: Liste aller nicht archivierten Ausgaben-Kategorien mit Fortschrittsbalken für den laufenden Monat; Tippen → Limit setzen/entfernen (Ziffernblock aus Task 10 wiederverwenden).

- [ ] **Step 1: Failing Tests**

```swift
@Test func overviewWarningsOnlyWarningAndExceeded()
@Test func recentLimitedToFiveOfMonth()
@Test func byPersonUsesDisplayNames()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Live-Prüfung** – iPhone und iPad, Hell/Dunkel, Dynamic Type „XXL“. Screenshots.
- [ ] **Step 6: Commit** – `feat(ios): overview and budgets`

---

### Task 13: „Mehr“ – Kategorien, Wiederkehrende, Export, Mitglieder, Sync-Status, Face ID, Abmelden

**Files:**
- Create: `Sources/HaushaltsbuchUI/More/{MoreView,CategoriesView,CategoryEditView,RecurringRulesView,RuleEditView,ExportView,MembersView,MemberEditView,ServerStatusView}.swift`, `Sources/HaushaltsbuchUI/AppLock.swift`
- Test: `Tests/HaushaltsbuchUITests/AppLockTests.swift`, `RuleDraftTests.swift`

**Interfaces:**
- Consumes: Repository (6), `CSVExport` (5), `AuthService.client` (7, Mitglieder online), `SyncEngine.status` (8), `AppModel` (9).
- Kategorien: Liste je Art, Name/Symbol (Auswahl aus fester Liste von ~30 SF Symbols)/Farbe (feste Palette 12 Farben), Verschieben (`onMove` → `moveCategories`), Entfernen → `removeCategory` mit Hinweis, ob archiviert oder gelöscht.
- Wiederkehrende: Liste mit nächstem Termin (`nextDueDate`, „wird vom Server berechnet“ wenn `nil`), Bearbeiten (Betrag, Art, Kategorie, Notiz, bezahlt von, Häufigkeit wöchentlich/monatlich/jährlich, Start, optional Ende). Validierung wie Server: Start ≥ 01.01.2000, Ende ≥ Start → `struct RuleDraft { func validationError() -> String? }`.
- Export: Zeitraum (Dieser Monat / Letzter Monat / Dieses Jahr / Frei), `ShareLink` mit Datei aus `CSVExport` (temporäre Datei mit `fileName`).
- Mitglieder (nur Admin, online): Liste (`listUsers`), anlegen (`createUser`), Anzeigename/Admin/Passwort zurücksetzen/Entfernen (`updateUser`, `deleted: true`, Bestätigungsdialog); Fehlercodes `username_taken`, `last_admin`, `cannot_delete_self` mit deutschen Meldungen; offline → Hinweis „Nur mit Verbindung zum Server möglich“.
- Server & Sync: Server-URL, angemeldeter Benutzer, Status, ausstehende Änderungen, „Jetzt synchronisieren“.
- Face ID: `@MainActor final class AppLock: ObservableObject` – `isEnabled` (UserDefaults), `isLocked`; sperrt bei `scenePhase == .background` wenn aktiv; `func unlock() async` über `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`; `protocol BiometricAuthenticating` für Tests.
- Abmelden: Sync versuchen; bleiben ausstehende Änderungen → Bestätigung „N ungesendete Änderungen gehen verloren“; dann `AuthService.logout()`, Store leeren, Cursor zurücksetzen.

- [ ] **Step 1: Failing Tests**

```swift
@Test func locksOnBackgroundWhenEnabled()
@Test func doesNotLockWhenDisabled()
@Test func unlockFailureStaysLocked()
@Test func ruleDraftRejectsStartBefore2000()
@Test func ruleDraftRejectsEndBeforeStart()
```
- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Live-Prüfung** – Mitglied anlegen und entfernen, wiederkehrende Miete (monatlich, Start heute) anlegen → nach Sync erscheint die erzeugte Buchung; CSV über Teilen-Menü in „Dateien“ sichern; Face ID im Simulator (Features → Face ID → Enrolled) sperren/entsperren. Screenshots.
- [ ] **Step 6: Commit** – `feat(ios): settings, members, export and app lock`

---

### Task 14: Ende-zu-Ende-Prüfung und Doku

**Files:**
- Create: `docs/ios.md`
- Modify: ggf. kleine Fixes aus der Prüfung (eigene Commits)

**Interfaces:**
- Consumes: alles.

- [ ] **Step 1: Server starten** (lokale `.env`, `DATA_DIR`/`BACKUP_DIR` außerhalb OneDrive).
- [ ] **Step 2: Zwei Geräte** – iPhone-17- und iPad-Simulator parallel; Admin auf dem iPhone, zweites Mitglied anlegen, auf dem iPad anmelden.
- [ ] **Step 3: Offline-Szenario** – `docker compose stop api`; auf beiden Geräten Buchungen erfassen → Banner „Nicht mit NAS verbunden – N Änderungen ausstehend“; `docker compose start api` → beide sehen alle Buchungen (innerhalb des Backoffs bzw. per Pull-to-Refresh).
- [ ] **Step 4: Konflikt** – dieselbe Buchung offline auf beiden Geräten ändern → nach dem Sync zeigen beide den zuletzt gesendeten Stand.
- [ ] **Step 5: Schnellerfassung messen** – vom Tipp auf „+“ bis gespeichert ≤ 3 Sekunden bei geübter Bedienung (Betrag + Kategorie).
- [ ] **Step 6: `docs/ios.md`** – Projekt erzeugen (`brew install xcodegen`, `cd ios && xcodegen generate`), Tests (`ios/scripts/test.sh`), auf eigene Geräte installieren (Team in Xcode wählen, kostenloser Account → 7 Tage gültig; Developer Program → 1 Jahr/TestFlight), Server-Adresse (LAN-IP/`.local`/VPN-IP mit Port 3000), `sync-openapi.sh` nach Server-Änderungen.
- [ ] **Step 7: Gesamtlauf** – `ios/scripts/test.sh` → PASS, `ios/scripts/sync-openapi.sh --check` → 0, `cd server && npm test` → PASS. `docker compose down`.
- [ ] **Step 8: Commit** – `docs(ios): build and install guide`
