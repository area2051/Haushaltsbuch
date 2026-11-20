# Design: Unterkategorien

Stand: 2026-11-20 · Status: freigegeben


## Context
Kategorien sind heute eine flache Liste (`categories`: name, icon, color, kind, sortOrder, archived). Buchungen, Regeln und Budgets hängen an genau einer Kategorie; Auswertungen gruppieren danach. Der Nutzer will **genauer auswerten** (z. B. wie viel von „Wohnen“ auf Strom, Gas, Grundsteuer entfällt) und dafür Unterkategorien – mit sinnvollen **Standard-Unterkategorien, die vorab angelegt** werden, auch auf der bestehenden NAS-Installation.

Erfolg: Man bucht „Wohnen · Strom“ so schnell wie heute „Wohnen“, und Übersicht/Trends/Export zeigen die Aufteilung innerhalb einer Hauptkategorie. Anti-Ziel: langsamere Schnellerfassung oder kaputter Sync für bestehende Daten/ältere App.

## Approaches
- **A – `parentId` an Kategorien (gewählt):** Unterkategorie = Kategorie mit Elternteil, eine Ebene. Erbt Sync, Löschschutz, Archiv, Icon. Ein Feld mehr im Protokoll, keine neue Tabelle.
- B – eigene Tabelle `subcategories` + `subcategoryId` an Buchungen/Regeln: sauber getrennt, aber neue Sync-Tabelle in Server/Web/iOS, ~doppelter Aufwand. Verworfen.
- Freitext/Tags: nicht verlässlich auswertbar. Verworfen.

## Entscheidungen (Nutzer)
- Zweck: genauer auswerten. Aufbau A. Standard-Unterkategorien werden beim Server-Update **einmalig automatisch** ergänzt. Verhalten und Liste unten bestätigt („Passt so“).

## Verhalten
- **Eine Ebene.** Unterkategorie hat dieselbe `kind` wie die Hauptkategorie; eine Kategorie mit Kindern kann nicht Unterkategorie werden; Elternteil muss existieren, nicht gelöscht, selbst ohne Elternteil sein.
- **Buchen:** Hauptkategorie wie heute; darunter Chip-Reihe „Allgemein“ + Unterkategorien (Standard „Allgemein“ = Buchung auf Hauptkategorie). Gilt für Erfassung, Bearbeiten, Regeln. Command Palette / Suche findet auch Unterkategorien.
- **Auswerten:** Übersicht, Budgets, Trends rollen Unterkategorien in die Hauptkategorie; Tipp auf eine Kategorie klappt Aufteilung auf („Allgemein“ + je Unterkategorie). Buchungsliste zeigt „Wohnen · Strom“, Filter auf Haupt- (inkl. Kinder) oder Unterkategorie. CSV-Export: neue Spalte „Unterkategorie“ (Spalte „Kategorie“ = Hauptkategorie).
- **Budgets** bleiben auf Hauptkategorien und zählen Kinder mit (kein Budget auf Unterkategorien – Server lehnt ab).
- **Verwalten:** Unterkategorien eingerückt unter der Hauptkategorie; anlegen, umbenennen, Icon, verschieben (anderer Elternteil gleicher Art), archivieren. Farbe = Farbe der Hauptkategorie (Feld bleibt, wird beim Anlegen/Verschieben gesetzt; Anzeige nutzt Elternfarbe). Hauptkategorie mit aktiven (nicht gelöschten) Kindern löschen → abgelehnt (`category_has_children`). Archivierte Hauptkategorie ⇒ Kinder gelten als archiviert (Auswahl blendet sie aus).
- **Umhängen (Nutzer: erlaubt, „Budget wandert mit“):** Eine Hauptkategorie ohne Kinder kann Unterkategorie einer anderen Hauptkategorie gleicher Art werden (und eine Unterkategorie wieder Hauptkategorie). Hat sie ein Budget: hat der neue Elternteil keins, wird das Budget auf den Elternteil umgehängt; hat er schon eins, wird das Budget der umgehängten Kategorie gelöscht (meine Entscheidung, da nur ein Budget je Kategorie erlaubt ist). Die App zeigt das vor dem Speichern an. Serverseitig im selben Savepoint wie das Kategorie-Update.
- **Weitere Server-Regeln (meine Entscheidung):** Hauptkategorie und Kind im selben Push → Elternteil zuerst verarbeiten (Kategorien vor Prüfung nach `parentId` sortieren). `kind` einer Kategorie mit Kindern ist nicht änderbar (`invalid_parent`).
- **Trends (meine Entscheidung):** bleiben je Hauptkategorie (Rollup in `categoryTrend`); Aufteilung nur in Übersicht (Aufklappen) und Export.
- **Ältere iOS-Version** ignoriert `parentId` und zeigt Unterkategorien flach – bleibt nutzbar. Neue iOS-Version: `dataModelGeneration` 2 → 3 (einmal alles neu holen).

## Standard-Unterkategorien (`server/src/setup/defaultCategories.ts`)
| Hauptkategorie | Unterkategorien |
|---|---|
| Lebensmittel | Supermarkt, Bäckerei, Getränke |
| Wohnen | Miete/Kredit, Nebenkosten, Strom, Gas, Wasser, Grundsteuer, Internet & Telefon, Einrichtung, Reparaturen |
| Mobilität | Tanken/Laden, Werkstatt, Versicherung & Steuer, ÖPNV, Parken |
| Freizeit | Restaurant & Café, Ausflüge, Hobbys, Urlaub, Kultur & Events |
| Gesundheit | Apotheke, Arzt & Zahnarzt, Brille |
| Kleidung | Bekleidung, Schuhe |
| Abos | Streaming, Musik, Zeitungen & Apps, Mitgliedschaften |
| Sonstiges | Geschenke, Drogerie & Haushalt, Spenden, Gebühren |
| Sonstige Einnahmen | Erstattungen, Zinsen, Verkäufe |
Icons: SF-Symbol-Namen aus dem bestehenden Icon-Set (`web/src/domain/icons`), fehlende ergänzen (Web-Mapping + iOS).
- **Neuinstallation:** Setup legt Haupt- und Unterkategorien an.
- **Bestehende Installation:** eigene SQL-Migration (drizzle `--custom`): fügt Unterkategorien nur unter nicht gelöschten Kategorien mit passendem Namen und passender `kind` ein, die noch keine Kinder haben; ein Name, den es bei dieser Art schon als (nicht gelöschte) Kategorie gibt, wird übersprungen (Nutzer: „Überspringen“). `version` kommt aus `sync_version_seq` (Default) → Geräte bekommen sie per Sync. Auf leerer DB No-op.

## Umsetzung (TDD, Branch `feat/subcategories`)
1. **Spec** nach `docs/superpowers/specs/2026-11-20-unterkategorien-design.md` (Inhalt dieses Plans), committen.
2. **Server**
   - `server/src/db/schema.ts`: `parentId: uuid('parent_id').references(() => categories.id)` (nullable) + Index; Migration via `npm run db:generate`, danach Custom-Migration für Standard-Unterkategorien.
   - `server/src/sync/schemas.ts`: `parentId` nullable, beim Push optional (fehlt → gespeicherter Wert bleibt, wie `interval`); Out: Pflicht/nullable.
   - `server/src/sync/service.ts` `upsertCategory`: Regeln oben prüfen (neue Rejections `invalid_parent`, `category_has_children`); `reviveCategory` belebt bei Bedarf auch den Elternteil; Budget auf Unterkategorie → `invalid_record`/eigener Grund. Pull-Select um `parentId`.
   - `server/src/setup/defaultCategories.ts` + `setup/routes.ts`: verschachtelte Defaults.
   - Tests: `server/test/sync.test.ts`, `setup`-Test, Migrationstest (bestehende Daten → Unterkategorien angelegt, umbenannte/gelöschte Hauptkategorien unberührt, zweiter Lauf nicht doppelt). `npm run openapi`.
3. **Web**
   - `npm run api`; Domain-Helfer `web/src/domain/categories.ts` (neu): `rootOf`, `childrenOf`, `labelFor` („Wohnen · Strom“), `rollup`.
   - `web/src/domain/analytics.ts`: Gruppierung nach Hauptkategorie + Aufteilung je Kind; `budgets/model.ts`, `overview/model.ts`, `transactions/list.ts` (Filter), `domain/csv.ts` (Spalte).
   - UI: `quickEntry/EntrySheet.tsx` + `draft.ts` (Chip-Reihe), `more/Categories.tsx` + `categoryOps.ts` (eingerückt, Elternteil wählen, Lösch-Sperre), `more/Recurring.tsx`, `palette/CommandPalette.tsx`, Overview-Aufklappen.
4. **iOS** (`ios/scripts/sync-openapi.sh`, Client neu generieren)
   - `CategoryEntity.parentId: UUID?` (SwiftData-Migration automatisch), `SyncMapping`, `dataModelGeneration = 3` in `HaushaltsbuchData/SyncEngine.swift`.
   - `HaushaltsbuchCore/Analytics.swift` + `CSVExport.swift`: Rollup/Spalte, Tests wie im Web.
   - UI: `QuickEntryModel/View`, `TransactionEditModel/View`, `RuleEditModel/View` (Chips), `CategoriesView`/`CategoryEditView` (Elternteil), `OverviewView/Model` (Aufklappen), `TransactionListModel` (Label/Filter), `BudgetEditView` (nur Hauptkategorien).
5. **Doku:** Design-Spec §3/§5, `docs/web.md`, `docs/betrieb.md` (Update-Reihenfolge: Server zuerst, dann iOS).
6. **Review** (superpowers:requesting-code-review), PR, CI.

Dem Builder überlassen: genaue Icon-Namen, Darstellung der Aufteilung (Liste vs. Mini-Donut), Reihenfolge der Kinder (sortOrder je Elternteil).

## Verifikation
- `cd server && npm test && npm run typecheck` (Migration gegen echtes Postgres inkl. Bestandsdaten, openapi-Aktualität).
- `cd web && npm test && npm run typecheck && npm run build`.
- `cd ios && scripts/test.sh`.
- Manuell (Browser-Pane, lokale Dev-DB mit Demo-Daten vor der Migration): Server starten → Standard-Unterkategorien erscheinen; „Wohnen · Strom“ erfassen; Übersicht klappt Wohnen auf; Budget Wohnen zählt Strom mit; Export hat Spalte; Hauptkategorie mit Kindern löschen wird verhindert.
- CI auf dem PR grün.
