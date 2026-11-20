# Unterkategorien Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kategorien bekommen eine Ebene Unterkategorien (`parentId`), Auswertungen rollen sie in die Hauptkategorie und zeigen die Aufteilung; Standard-Unterkategorien werden bei Neuinstallation und einmalig auf Bestandsinstallationen angelegt.

**Architecture:** Ein nullable Feld `parentId` an `categories` (Server, Sync-Protokoll, Web, iOS). Der Server erzwingt die Baumregeln pro Datensatz im bestehenden Savepoint-Muster (`Rejection`). Clients nutzen einen kleinen Baum-Helfer (`rootOf`, `childrenOf`, `labelFor`) und reichen eine `rootOf`-Funktion an die bestehenden Analytics-Funktionen.

**Tech Stack:** Fastify + Drizzle + Postgres 17 + zod (Vitest, Testcontainers); React 19 + Vite + TS (Vitest, Testing Library); SwiftUI + SwiftData (Swift Testing).

**Spec:** `docs/superpowers/specs/2026-11-20-unterkategorien-design.md`

## Global Constraints
- Genau eine Ebene; Unterkategorie hat dieselbe `kind` wie die Hauptkategorie.
- Push: `parentId` optional (fehlt → gespeicherter Wert bleibt, neu → `null`); Out: `parentId: string | null` Pflicht.
- Neue Rejection-Gründe (exakt): `invalid_parent`, `category_has_children`, `budget_on_subcategory`.
- Budgets nur auf Hauptkategorien; Budget einer Hauptkategorie zählt ihre Unterkategorien mit.
- Anzeige-Label: `"Wohnen · Strom"` (Mittelpunkt U+00B7 mit Leerzeichen). Auswahl-Chip für die Hauptkategorie selbst: `"Allgemein"`.
- CSV-Kopf (exakt): `Datum;Art;Kategorie;Unterkategorie;Betrag;Notiz;Bezahlt von`.
- iOS `dataModelGeneration = 3`.
- Trends bleiben je Hauptkategorie; Aufteilung nur in Übersicht (Aufklappen) und Export.
- Standard-Unterkategorien und Icons: Tabelle in Task 3 (eine Quelle: `server/src/setup/defaultCategories.ts`).
- Update-Reihenfolge: Server zuerst, dann iOS.

## Review Focus
1. Push mit neuer Hauptkategorie **und** Kind im selben Request, Kind in der Liste zuerst → beide angenommen (Task 2).
2. Push löscht Kind und Hauptkategorie zusammen (Hauptkategorie zuerst in der Liste) → beide gelöscht (Task 2).
3. Kategorie mit Budget wird unter eine Hauptkategorie gehängt, die schon ein Budget hat → altes Budget gelöscht, kein `unique_violation` (Task 2).
4. Bestandsinstallation mit eigener Kategorie „Strom“ → Migration legt „Wohnen · Strom“ nicht an (Task 3).
5. Archivierte Hauptkategorie → ihre Unterkategorien erscheinen in keiner Auswahl, alte Buchungen zeigen trotzdem das Label (Task 4/Task 8).

---

### Task 1: Server – Spalte `parent_id` und Protokollfeld

**Files:**
- Modify: `server/src/db/schema.ts` (categories), `server/src/sync/schemas.ts`, `server/src/sync/service.ts` (pull select)
- Create: Migration via `npm run db:generate` → `server/drizzle/0003_*.sql`
- Test: `server/test/sync.test.ts`, `server/test/schema.test.ts`

**Interfaces:**
- Produces: `categories.parentId` (`uuid('parent_id').references(() => categories.id)`, nullable) + `index('categories_parent_idx')`; `CategoryRecord.parentId?: string | null`; `CategoryRecordOut.parentId: string | null`.

- [ ] **Step 1: Failing tests** in `sync.test.ts`:
  - `test('category parentId round-trips and defaults to null')`: Push Kategorie ohne `parentId` → Pull hat `parentId: null`; Push Kind mit `parentId: <Lebensmittel-id>` → Pull liefert diese id.
  - `test('push without parentId keeps the stored parent')`: Kind anlegen, erneut ohne `parentId` pushen (alte App) → `parentId` unverändert.
- [ ] **Step 2:** `cd server && npx vitest run test/sync.test.ts -t parentId` → FAIL.
- [ ] **Step 3:** Schema-Spalte + Index, `npm run db:generate`; `categoryRecord` bekommt `parentId: id.nullable().optional()`, `categoryRecordOut` `parentId: outId.nullable()`; `upsertCategory` setzt `parentId = r.parentId === undefined ? existing?.parentId ?? null : r.parentId`; Pull-Select um `parentId`.
- [ ] **Step 4:** Tests grün; `npm test && npm run typecheck`.
- [ ] **Step 5:** `npm run openapi`; Commit `feat(server): category parentId`.

### Task 2: Server – Baumregeln in `upsertCategory`, Budgets, Reihenfolge

**Files:**
- Modify: `server/src/sync/service.ts`
- Test: `server/test/sync.test.ts` (neuer `describe('subcategories')`)

**Interfaces:**
- Consumes: Task 1.
- Produces: Rejection-Gründe aus Global Constraints; `applySync` sortiert Nicht-Lösch-Kategorien „ohne `parentId` zuerst“ und Löschungen „mit `parentId` zuerst“.

- [ ] **Step 1: Failing tests** (je ein `test`, Namen exakt):
  - `rejects parent that does not exist or is deleted` → `invalid_parent`
  - `rejects parent that itself has a parent` → `invalid_parent`
  - `rejects parent of the other kind` → `invalid_parent`
  - `rejects giving a parent to a category that has children` → `invalid_parent`
  - `rejects changing kind of a category with children` → `invalid_parent`
  - `rejects self as parent` → `invalid_parent`
  - `rejects deleting a category with active children` → `category_has_children`; nach Löschen des Kindes klappt es
  - `accepts parent and child in one push in any order` (Review Focus 1)
  - `deletes child and parent in one push in any order` (Review Focus 2)
  - `rejects budget on a subcategory` → `budget_on_subcategory`
  - `moving a budgeted category under a parent without budget moves the budget` → Budget.categoryId == Elternteil, neue Version
  - `moving a budgeted category under a parent with budget deletes its budget` (Review Focus 3)
  - `transaction on a deleted subcategory revives it and its deleted parent` → beide `deleted:false, archived:true`
- [ ] **Step 2:** `npx vitest run test/sync.test.ts -t subcategories` → FAIL.
- [ ] **Step 3:** Implementieren:
  - `async function checkParent(sp, r, existing): Promise<void>` (wirft `Rejection('invalid_parent')`): Elternteil existiert, nicht gelöscht, `parentId` des Elternteils `null`, gleiche `kind`, ≠ eigene id; hat `r` aktive Kinder → `parentId` muss `null` sein und `kind` darf sich nicht ändern.
  - Löschen: aktive Kinder → `Rejection('category_has_children')` (vor `category_in_use`-Prüfung).
  - Nach dem Upsert, wenn `parentId` neu gesetzt wurde: `async function rehomeBudget(sp, childId, parentId)` – aktives Budget des Kindes auf Elternteil umhängen, falls Elternteil keins hat, sonst löschen (beides mit `bump()`).
  - `upsertBudget`: Kategorie mit `parentId` → `Rejection('budget_on_subcategory')` (nur bei `!r.deleted`).
  - `reviveCategory`: nach Wiederbelebung auch den Elternteil wiederbeleben (rekursiv eine Ebene).
  - `applySync`: Sortierung wie oben (stabil).
- [ ] **Step 4:** Tests grün; Mutationscheck: je eine Regel auskommentieren → passender Test schlägt fehl.
- [ ] **Step 5:** Commit `feat(server): subcategory rules in sync`.

### Task 3: Server – Standard-Unterkategorien (Setup + einmalige Migration)

**Files:**
- Modify: `server/src/setup/defaultCategories.ts`, `server/src/setup/routes.ts`
- Create: `npx drizzle-kit generate --custom --name=default_subcategories` → `server/drizzle/0004_default_subcategories.sql`
- Test: `server/test/setup.test.ts`, Create `server/test/default-subcategories.test.ts`

**Interfaces:**
- Produces: `DefaultCategory` bekommt `children?: ReadonlyArray<{ name: string; icon: string }>`; Kinder erben `color`/`kind`, `sortOrder` = Index innerhalb des Elternteils.

Daten (Name → Icon; alle Icons existieren in `CATEGORY_SYMBOLS`):
| Hauptkategorie | Unterkategorien |
|---|---|
| Lebensmittel | Supermarkt cart · Bäckerei basket · Getränke cup.and.saucer |
| Wohnen | Miete/Kredit house · Nebenkosten building.columns · Strom bolt · Gas flame · Wasser drop · Grundsteuer building.columns · Internet & Telefon wifi · Einrichtung house · Reparaturen wrench.and.screwdriver |
| Mobilität | Tanken/Laden fuelpump · Werkstatt wrench.and.screwdriver · Versicherung & Steuer creditcard · ÖPNV bus · Parken car |
| Freizeit | Restaurant & Café fork.knife · Ausflüge bicycle · Hobbys gamecontroller · Urlaub airplane · Kultur & Events film |
| Gesundheit | Apotheke pills · Arzt & Zahnarzt cross.case · Brille heart |
| Kleidung | Bekleidung tshirt · Schuhe tshirt |
| Abos | Streaming film · Musik music.note · Zeitungen & Apps book · Mitgliedschaften person.2 |
| Sonstiges | Geschenke gift · Drogerie & Haushalt basket · Spenden heart · Gebühren eurosign |
| Sonstige Einnahmen | Erstattungen eurosign · Zinsen chart.line.uptrend.xyaxis · Verkäufe banknote |

- [ ] **Step 1: Failing tests**
  - `setup.test.ts`: `setup creates default subcategories under their parents` → 10 Hauptkategorien, 38 Kinder, „Strom“ hat `parentId` von „Wohnen“ und dessen Farbe.
  - `default-subcategories.test.ts` (führt den SQL-Text der Migrationsdatei per `db.execute(sql.raw(...))` aus):
    - `adds subcategories under untouched default categories` (Bestandsdaten = Hauptkategorien ohne Kinder) → 38 Kinder, Versionen > vorherige max-Version
    - `skips renamed or deleted parents` („Wohnen“ umbenannt in „Haus“ → keine Wohnen-Kinder)
    - `skips parents that already have children`
    - `skips names that already exist for that kind` (eigene Hauptkategorie „Strom“ → kein Kind „Strom“, andere Wohnen-Kinder schon) — Review Focus 4
    - `second run adds nothing`
    - `is a no-op on an empty database`
    - `matches DEFAULT_CATEGORIES` (Ergebnis auf leerer DB nach Insert der 10 Hauptkategorien == Kinderliste aus `defaultCategories.ts`, Name/Icon/Reihenfolge)
- [ ] **Step 2:** Tests → FAIL.
- [ ] **Step 3:** `defaultCategories.ts` + Setup-Insert (Hauptkategorien, dann Kinder mit `parentId`); Migration als ein `INSERT … SELECT` aus `VALUES (parent, kind, name, icon, ord)` mit `JOIN categories p ON p.name = parent AND p.kind = kind AND p.parent_id IS NULL AND NOT p.deleted` und `NOT EXISTS` (aktive Kinder von p) sowie `NOT EXISTS` (aktive Kategorie gleicher kind mit `lower(name) = lower(v.name)`); `color` = `p.color`; `version` per Default.
- [ ] **Step 4:** `npm test && npm run typecheck` grün.
- [ ] **Step 5:** Commit `feat(server): default subcategories`.

### Task 4: Web – Baum-Helfer, Analytics-Rollup, Liste, CSV

**Files:**
- Create: `web/src/domain/categoryTree.ts` + `.test.ts`
- Modify: `web/src/domain/analytics.ts`, `web/src/domain/csv.ts`, `web/src/features/transactions/list.ts` (+ zugehörige Tests)
- Vorher: `cd web && npm run api`

**Interfaces:**
- Produces (`categoryTree.ts`):
  - `type CategoryTree = { byId: Map<string, Category>; rootOf(id: string): string; childrenOf(id: string): Category[]; labelFor(id: string): string; isSelectable(c: Category): boolean }`
  - `function categoryTree(cats: Category[]): CategoryTree` – `childrenOf` nach `sortOrder`, Name; `rootOf` unbekannter id = id; `labelFor` „Haupt · Kind“ bzw. Name bzw. „Unbekannt“; `isSelectable` = nicht archiviert und Elternteil (falls vorhanden) nicht archiviert.
- `expensesByCategory(txs, m, rootOf: (id: string) => string = (id) => id)`, `budgetProgress(budgets, txs, m, rootOf = identity)`, `categoryTrend(txs, end, count, topN, rootOf = identity)`.
- `function subcategoryBreakdown(txs: Transaction[], m: Month, parentId: string, tree: CategoryTree): Total[]` (in `analytics.ts`; Buchungen direkt auf der Hauptkategorie unter `id = parentId`).
- `makeCsv(txs, tree: CategoryTree, members, from, to)` – Spalte „Kategorie“ = Hauptkategorie-Name, „Unterkategorie“ = Kindname oder leer.
- `TxFilter.categoryId` filtert Hauptkategorie inkl. Kinder bzw. genau ein Kind; `sections(txs, f, tree)`; Suche trifft auch das Label.

- [ ] **Step 1: Failing tests**: `categoryTree.test.ts` (rootOf/childrenOf/labelFor/isSelectable inkl. archivierter Elternteil – Review Focus 5), `analytics.test.ts` (`rolls subcategory expenses into their parent`, `budget counts subcategory spending`, `breakdown lists general and each child`, `category trend rolls up`), `csv.test.ts` (Kopf exakt, Kind-Buchung → `Wohnen;Strom`), `list.test.ts` (Filter Elternteil trifft Kinder, Filter Kind nur Kind, Suche „strom“).
- [ ] **Step 2:** `npx vitest run src/domain src/features/transactions` → FAIL.
- [ ] **Step 3:** Implementieren; Aufrufer mit `tree` versorgen (TypeScript führt).
- [ ] **Step 4:** `npm test && npm run typecheck` grün.
- [ ] **Step 5:** Commit `feat(web): category tree and rollup analytics`.

### Task 5: Web – Übersicht, Budgets, Verwaltungs-Logik

**Files:**
- Modify: `web/src/features/overview/model.ts`, `web/src/features/budgets/model.ts`, `web/src/features/more/categoryOps.ts` (+ Tests)

**Interfaces:**
- `Slice` bekommt `children: Slice[]` (aus `subcategoryBreakdown`, „Allgemein“ für die Hauptkategorie selbst, nur wenn > 0).
- `budgetRows`: nur Hauptkategorien; `spentCents` inkl. Kinder.
- `CategoryDraft.parentId: string | null`; `newCategory` setzt `color` = Elternfarbe, `sortOrder` innerhalb der Geschwister.
- `function moveCategory(c: Category, parentId: string | null, all: Category[]): CategoryInput` (Farbe des neuen Elternteils, `sortOrder` ans Ende).
- `function moveBudgetEffect(c: Category, parentId: string, budgets: Budget[]): 'none' | 'moves' | 'deleted'` (für den Hinweis vor dem Speichern).
- `removalPlan` → `{ action: 'blocked' }` wenn aktive Kinder existieren.
- `function parentOptions(c: Category | null, all: Category[], kind: Kind): Category[]` (Hauptkategorien gleicher Art, nicht archiviert, ≠ c; leer, wenn c Kinder hat).

- [ ] **Step 1: Failing tests** zu jeder Funktion oben (Werte aus der Spec).
- [ ] **Step 2:** FAIL. **Step 3:** Implementieren. **Step 4:** `npm test && npm run typecheck`.
- [ ] **Step 5:** Commit `feat(web): subcategories in overview, budgets and category ops`.

### Task 6: Web – UI

**Files:**
- Create: `web/src/components/SubcategoryChips.tsx` + `.test.tsx`
- Modify: `features/quickEntry/EntrySheet.tsx` (+ Test), Buchung bearbeiten (gleiche Sheet), `features/more/Recurring.tsx`, `features/more/Categories.tsx`, `features/palette/CommandPalette.tsx`, `features/overview/Overview.tsx`, `features/transactions/Transactions.tsx`, `features/budgets/*`, `features/more/Export.tsx`

**Interfaces:**
- `SubcategoryChips({ parentId, value, onChange, tree }: { parentId: string; value: string; onChange(id: string): void; tree: CategoryTree })` – erster Chip „Allgemein“ (= parentId), danach `childrenOf(parentId).filter(isSelectable)`; rendert nichts ohne wählbare Kinder.
- Kategorie-Auswahl zeigt nur Hauptkategorien; Wechsel der Hauptkategorie setzt auf „Allgemein“; Bearbeiten einer Kind-Buchung wählt Elternteil + Kind vor.

- [ ] **Step 1: Failing tests**: `SubcategoryChips.test.tsx` (Allgemein vorausgewählt, Klick setzt Kind, archiviertes Kind fehlt); `EntrySheet.test.tsx` `books on a subcategory` (gespeicherte Buchung hat Kind-id; Hauptkategorie-Wechsel → zurück auf Allgemein).
- [ ] **Step 2:** FAIL. **Step 3:** Chips einbauen (Erfassung, Bearbeiten, Regeln); Kategorienverwaltung: Kinder eingerückt, „Gehört zu“-Select aus `parentOptions`, Hinweis aus `moveBudgetEffect`, Löschen bei `blocked` deaktiviert mit Text „Erst Unterkategorien entfernen“; Palette listet Kinder mit Label; Übersicht: Tipp auf Slice klappt `children` auf; Liste/Budgets/Export nutzen Label bzw. Rollup.
- [ ] **Step 4:** `npm test && npm run typecheck && npm run build`.
- [ ] **Step 5:** Commit `feat(web): subcategory UI`.

### Task 7: iOS – Modell, Sync, Repository

**Files:**
- Run: `ios/scripts/sync-openapi.sh` (Client neu generieren)
- Modify: `HaushaltsbuchData/Models/CategoryEntity.swift` (`parentId: UUID?`), `SyncMapping.swift`, `SyncEngine.swift` (`dataModelGeneration = 3`), `Drafts.swift` (`CategoryDraft.parentId: UUID?`), `Repository.swift` (`saveCategory`, `deleteCategory` o. ä.), `HaushaltsbuchCore/Analytics.swift` (`CategoryValue.parentId: UUID?`)
- Test: `Tests/HaushaltsbuchAPITests/CodingTests.swift` (Fixture `"parentId": null`), `Tests/HaushaltsbuchDataTests/SyncEngineTests.swift`, `RepositoryTests.swift`

- [ ] **Step 1: Failing tests**: Decoding mit/ohne `parentId`; Sync übernimmt `parentId` und sendet es; Cursor-Key enthält `v3`; `saveCategory` mit Elternteil übernimmt Elternfarbe; Löschen einer Kategorie mit Kindern wirft `RepositoryError` (neuer Fall `hasChildren`).
- [ ] **Step 2:** `cd ios && scripts/test.sh` → FAIL. **Step 3:** Implementieren. **Step 4:** grün (bekannt flaky: `logoutSyncIsBounded`, `runBoundedReturnsEarlyWhenWorkFinishes`, `offlineLogoutRevokeIsBounded` – einzeln nachprüfen).
- [ ] **Step 5:** Commit `feat(ios): category parentId in model and sync`.

### Task 8: iOS – Core (Baum, Rollup, CSV) und UI

**Files:**
- Create: `HaushaltsbuchCore/CategoryTree.swift` + `Tests/HaushaltsbuchCoreTests/CategoryTreeTests.swift`
- Modify: `Analytics.swift`, `CSVExport.swift` (+ Tests), UI: `QuickEntryModel/View`, `TransactionEditModel/View`, `RuleEditModel/View`, `CategoriesView`, `CategoryEditView`, `OverviewModel/View`, `TransactionListModel/View`, `BudgetsView`, `BudgetEditView`, `ExportView`
- Test: `AnalyticsTests`, `CSVExportTests`, `OverviewModelTests`, `QuickEntryModelTests`, `TransactionListModelTests`, `MoreModelTests`

**Interfaces:** Spiegel von Task 4–6: `struct CategoryTree { init(_ cats: [CategoryValue]); func rootOf(_ id: UUID) -> UUID; func childrenOf(_ id: UUID) -> [CategoryValue]; func label(_ id: UUID) -> String; func isSelectable(_ c: CategoryValue) -> Bool }`; `Analytics.expensesByCategory(_:month:rootOf:)`, `budgetProgress(_:txs:month:rootOf:)`, `subcategoryBreakdown(_:month:parentId:tree:)`; `CSVExport.make(_:tree:members:from:to:)` mit dem Kopf aus Global Constraints. UI: `SubcategoryChipsView` analog Web.

- [ ] **Step 1: Failing tests**: dieselben Fälle wie Task 4/5 (Testnamen übernehmen), plus `QuickEntryModelTests.booksOnSubcategory`, `OverviewModelTests.sliceHasSubcategoryBreakdown`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementieren. **Step 4:** `scripts/test.sh` grün.
- [ ] **Step 5:** Commit `feat(ios): subcategories in analytics, export and UI`.

### Task 9: Doku, Gesamtprüfung, Review, PR

**Files:** `docs/superpowers/specs/2026-11-01-haushaltsbuch-design.md` (§3 Datenmodell `parentId`, §5 Rejection-Gründe), `docs/web.md`, `docs/betrieb.md` (Update: Server zuerst, dann iOS; Migration ergänzt Unterkategorien einmalig).

- [ ] **Step 1:** Doku anpassen.
- [ ] **Step 2:** `cd server && npm test && npm run typecheck`; `cd web && npm test && npm run typecheck && npm run build`; `cd ios && scripts/test.sh` – alles grün.
- [ ] **Step 3:** Manuell (Browser-Pane, Dev-DB auf Stand `main` mit Demo-Daten, dann Branch-Server starten): Unterkategorien erscheinen; „Wohnen · Strom“ erfassen; Übersicht klappt Wohnen auf; Budget Wohnen zählt Strom; Export-Spalte; Löschen von Wohnen gesperrt.
- [ ] **Step 4:** superpowers:requesting-code-review über den ganzen Branch; Befunde mit superpowers:receiving-code-review abarbeiten.
- [ ] **Step 5:** Commit Doku; nach Rückfrage push + PR, CI grün.
