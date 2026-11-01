# Haushaltsbuch – Design-Spezifikation

Stand: 2026-11-01 · Status: zur Freigabe

## 1. Ziel & Rahmen

Native Apple-App (iPhone + iPad) als Haushaltsbuch für **einen** Haushalt mit mehreren Personen, mit **eigenem TypeScript-API-Backend**, das auf der **UGREEN-NAS** zu Hause läuft.

- **Motivation:** Backend selbst bauen und dabei lernen; Daten unter eigener Kontrolle (nicht bei Apple oder einem Cloud-Anbieter).
- **Produktfokus:** schnelles Erfassen – eine Buchung in ca. 3 Sekunden.
- **Netz:** Die API ist nie öffentlich erreichbar. Zu Hause per LAN, unterwegs über ein VPN zur NAS, das der Nutzer selbst einrichtet. Die App kennt nur eine konfigurierbare Server-URL.
- **Offline-first:** Die App funktioniert vollständig ohne Verbindung und synchronisiert, sobald der Server erreichbar ist.
- **Ein Haushalt pro Server.** Alle Konten auf dem Server gehören zum selben Haushalt.
- Währung nur EUR, Sprache Deutsch.

### Umfang v1
- Einnahmen/Ausgaben erfassen, bearbeiten, löschen; eigene Kategorien; „bezahlt von“ pro Buchung
- Monatsübersicht mit Diagrammen (nach Kategorie, nach Person)
- Budgets pro Kategorie (Monatslimit)
- Wiederkehrende Buchungen
- CSV-Export

### Nicht in v1
- Schuldenausgleich zwischen Personen („wer schuldet wem“)
- Mehrere Haushalte pro Server, mehrere Währungen
- Widget, Siri-Kurzbefehl (Architektur soll es nicht verbauen)
- Belege/Fotos, Bankanbindung, Push-Benachrichtigungen
- Web-Oberfläche

## 2. Architektur

Monorepo:

```
ios/                  Xcode-Projekt, SwiftUI, Universal-App (iPhone + iPad), iOS 18+
server/               TypeScript: Fastify + Drizzle ORM + zod, Logs mit pino
server/openapi.json   generierter API-Vertrag (aus den zod-Schemas), eingecheckt
docker-compose.yml    api + postgres + backup
docs/                 Spezifikationen, Pläne, Betriebsanleitung
```

### App (ios/)
Drei Schichten mit klaren Grenzen:

1. **Views (SwiftUI)** – lesen ausschließlich aus SwiftData, schreiben ausschließlich über ein Repository.
2. **Lokaler Speicher (SwiftData)** – alle Daten liegen lokal. Jede lokale Änderung setzt am Datensatz `isDirty = true`.
3. **SyncEngine + APIClient** – der APIClient wird mit Apples `swift-openapi-generator` aus `server/openapi.json` erzeugt. Die SyncEngine überträgt Dirty-Datensätze und übernimmt Server-Änderungen in SwiftData.

Zugangsdaten (Server-URL, Access-/Refresh-Token) liegen im Schlüsselbund.

### Server (server/)
- Fastify-Routen mit zod-Schemas; daraus wird `openapi.json` erzeugt (z. B. `fastify-type-provider-zod` + `@fastify/swagger`). Ein npm-Skript schreibt die Datei; ein Test schlägt fehl, wenn die eingecheckte Datei veraltet ist.
- PostgreSQL 17 über Drizzle ORM; Migrationen mit drizzle-kit, ausgeführt beim Serverstart.
- Auth: JWT. Access-Token 15 Minuten, Refresh-Token 90 Tage, bei jeder Erneuerung rotiert (altes Token wird ungültig). Passwörter mit argon2id, Mindestlänge 8.
- Strukturierte JSON-Logs (pino).

## 3. Datenmodell

Alle synchronisierten Tabellen haben:

| Feld | Bedeutung |
|---|---|
| `id uuid` | vom Client erzeugt (Server erzeugt sie nur für eigene Datensätze) |
| `version bigint` | vom Server bei jeder Änderung vergeben, aus einer gemeinsamen Postgres-Sequence |
| `deleted bool` | Soft-Delete; gelöschte Datensätze bleiben als Markierung erhalten |
| `created_at`, `updated_at` | Zeitstempel (nur Information, nicht für den Sync) |

Tabellen:

- **users** – `username` (eindeutig), `display_name`, `password_hash`, `is_admin`. Wird an die App nur lesend und ohne `password_hash` synchronisiert.
- **refresh_tokens** – `user_id`, `token_hash`, `expires_at`, `device_name`. Nicht synchronisiert.
- **categories** – `name`, `icon` (SF-Symbol-Name), `color` (Hex), `kind` (`income` | `expense`), `sort_order`, `archived`.
  - Eine Kategorie ohne Buchungen wird gelöscht (`deleted`), eine mit Buchungen nur archiviert. Archivierte Kategorien erscheinen nicht in der Erfassung, alte Buchungen behalten sie.
- **transactions** – `amount_cents` (Integer > 0), `kind`, `category_id`, `date` (Kalenderdatum `YYYY-MM-DD`, ohne Uhrzeit), `note` (optional), `paid_by` (user_id), `recurring_rule_id` (optional).
  - Eindeutigkeit `(recurring_rule_id, date)`, wenn `recurring_rule_id` gesetzt ist.
- **budgets** – `category_id` (eindeutig unter nicht gelöschten), `monthly_limit_cents`.
- **recurring_rules** – `amount_cents`, `kind`, `category_id`, `note`, `paid_by`, `frequency` (`weekly` | `monthly` | `yearly`), `start_date`, `end_date` (optional), `next_due_date`.
  - `weekly`: gleicher Wochentag wie `start_date`.
  - `monthly`: gleicher Tag des Monats wie `start_date`; gibt es den Tag nicht (z. B. 31.), dann der letzte Tag des Monats.
  - `yearly`: gleicher Tag und Monat wie `start_date`; 29. Februar → 28. Februar in Nicht-Schaltjahren.

**Standard-Kategorien** (beim ersten Setup angelegt): Ausgaben – Lebensmittel, Wohnen, Mobilität, Freizeit, Gesundheit, Kleidung, Abos, Sonstiges; Einnahmen – Gehalt, Sonstige Einnahmen.

## 4. Sync-Protokoll

Ein Endpunkt `POST /sync` für beide Richtungen.

**Request:**
```json
{
  "lastVersion": 1234,
  "changes": {
    "categories":      [ { "id": "…", "deleted": false, "...": "…" } ],
    "transactions":    [ … ],
    "budgets":         [ … ],
    "recurringRules":  [ … ]
  }
}
```

**Ablauf auf dem Server** (in einer DB-Transaktion, serialisiert per `pg_advisory_xact_lock`, damit Versionen lückenlos in Commit-Reihenfolge sichtbar werden):
1. Jeden übermittelten Datensatz mit zod prüfen. Ungültige Datensätze werden einzeln abgelehnt, der Rest wird übernommen.
2. Gültige Datensätze per Upsert anhand der `id` schreiben; jeder bekommt eine neue `version`. Konfliktregel: **Last-Write-Wins** – die zuletzt beim Server eintreffende Änderung gewinnt.
   - Löschen einer Kategorie, auf die noch aktive Buchungen oder Regeln zeigen, wird mit `category_in_use` abgelehnt.
   - Trifft eine Buchung, Regel oder ein Budget für eine bereits gelöschte Kategorie ein (anderes Gerät war offline), wird die Kategorie als archiviert wiederhergestellt und der Datensatz angenommen.
   - `next_due_date` wiederkehrender Regeln setzt nur der Server.
3. Hat der Push wiederkehrende Regeln geändert, läuft danach sofort die Erzeugung wiederkehrender Buchungen (Abschnitt 5).
4. Alle Datensätze aller Sync-Tabellen (inkl. `users` ohne Passwort-Hash, inkl. gelöschter) mit `version > lastVersion` zurückgeben – auch die gerade geschriebenen.
5. Ist `lastVersion` größer als die höchste Version auf dem Server (z. B. nach Wiederherstellung eines Backups), antwortet der Server mit `fullResync: true` und dem vollständigen Datenbestand; die App ersetzt dann ihren Stand (ungesendete lokale Änderungen werden vorher übertragen). Dasselbe gilt, wenn `lastVersion` > 0 unter der Resync-Grenze `sync_meta.resync_floor` liegt, die die Wiederherstellungsprozedur setzt (siehe docs/betrieb.md); ohne sie könnten nach einer Wiederherstellung neu vergebene Versionen von Geräten übersprungen werden.

**Response:**
```json
{
  "currentVersion": 1302,
  "fullResync": false,
  "changes":  { "categories": […], "transactions": […], "budgets": […], "recurringRules": […], "users": […] },
  "rejected": [ { "table": "transactions", "id": "…", "reason": "amount_cents must be > 0" } ]
}
```

**Client:**
- Übernimmt `changes` in SwiftData. Ein lokal noch dirty Datensatz wird **nicht** von einer Server-Version überschrieben, die vor seiner Übertragung stammt: Die Engine sendet erst, verarbeitet dann die Antwort; übertragene Datensätze werden nur dann auf `isDirty = false` gesetzt, wenn sie seit dem Absenden nicht erneut geändert wurden.
- Speichert `currentVersion` als neuen `lastVersion`.
- Markiert abgelehnte Datensätze sichtbar („konnte nicht gespeichert werden“) und lässt sie lokal bearbeiten oder verwerfen.
- **Idempotenz:** Wiederholt die App denselben Push (z. B. nach Timeout), entstehen dank der Client-UUIDs keine Duplikate.
- **Auslöser:** App-Start, Rückkehr in den Vordergrund, 2 Sekunden nach der letzten lokalen Änderung, Netz wieder verfügbar, Pull-to-Refresh. Fehlgeschlagene Versuche werden mit zunehmender Wartezeit wiederholt (bis max. 5 Minuten).

## 5. Wiederkehrende Buchungen

- Erzeugt **nur der Server**: täglich um 03:00 (Europe/Berlin) per In-Process-Scheduler sowie direkt nach einem Sync, der Regeln geändert hat.
- Für jede aktive, nicht gelöschte Regel: solange `next_due_date <= heute` und (`end_date` leer oder `next_due_date <= end_date`): Buchung mit `date = next_due_date` und `recurring_rule_id` anlegen, `next_due_date` weiterschalten. Die Eindeutigkeit `(recurring_rule_id, date)` verhindert Duplikate auch bei Wiederholung.
- Nachholen: War der Server mehrere Tage aus, werden alle verpassten Termine nachgeholt.
- Erzeugte Buchungen sind normale Buchungen und können bearbeitet oder gelöscht werden. Eine gelöschte erzeugte Buchung wird nicht neu erzeugt.

## 6. API-Endpunkte

| Methode & Pfad | Zweck | Auth |
|---|---|---|
| `GET /health` | Erreichbarkeit + `setupRequired: bool` | keine |
| `POST /setup` | erstes Admin-Konto anlegen + Standard-Kategorien; nur solange kein User existiert, sonst 409 | keine |
| `POST /auth/login` | Benutzername + Passwort → Access- + Refresh-Token | keine |
| `POST /auth/refresh` | Refresh-Token → neues Token-Paar (Rotation) | Refresh-Token |
| `POST /auth/logout` | Refresh-Token widerrufen | Access-Token |
| `GET /me`, `PATCH /me` | eigenes Profil; Anzeigename und Passwort ändern (altes Passwort nötig) | Access-Token |
| `GET /users`, `POST /users`, `PATCH /users/{id}` | Mitglieder verwalten, Passwort zurücksetzen, Admin-Recht vergeben | Admin |
| `POST /sync` | Abschnitt 4 | Access-Token |

Login-Schutz: nach 5 Fehlversuchen pro Benutzername 1 Minute Sperre.

## 7. App: Screens & Bedienung

### Onboarding
Server-URL eingeben (z. B. `http://nas.local:3000` oder VPN-IP) → `GET /health` → bei `setupRequired` Admin-Konto anlegen, sonst anmelden → erster vollständiger Sync (`lastVersion = 0`).

### Schnellerfassung (Kernfunktion)
- iPhone: „+“-Button in der Mitte der Tab-Leiste. iPad: Button in der Toolbar und Tastaturkürzel ⌘N.
- Öffnet ein Sheet, das sofort den **Ziffernblock** zeigt. Der Betrag wird von rechts eingetippt (`1`,`2`,`5`,`0` → 12,50 €); Löschtaste entfernt die letzte Ziffer.
- Darunter ein **Kategorie-Raster**, sortiert nach Nutzungshäufigkeit der letzten 90 Tage. **Ein Tipp auf eine Kategorie speichert sofort** – mit heutigem Datum, Art „Ausgabe“ und „bezahlt von: ich“. Ohne Betrag > 0 ist das Raster deaktiviert.
- Einklappbarer Bereich „Details“: Ausgabe/Einnahme, Datum, bezahlt von, Notiz. Ein Wechsel auf „Einnahme“ zeigt die Einnahme-Kategorien.
- Nach dem Speichern: Haptik-Feedback, Sheet schließt sich.

### Navigation
iPhone: Tab-Leiste. iPad: `NavigationSplitView` (Seitenleiste – Liste – Detail).

1. **Übersicht** – Monatswähler (Wischen/Pfeile), Saldo mit Einnahmen und Ausgaben, Donut-Diagramm der Ausgaben nach Kategorie, Balken der Ausgaben nach Person, Budget-Warnungen ab 80 % und 100 %, die letzten 5 Buchungen. Auf dem iPad mehrere Diagramme nebeneinander.
2. **Buchungen** – Liste nach Tagen gruppiert, Suche in der Notiz, Filter nach Kategorie, Person und Art. Wischen zum Löschen, Tippen zum Bearbeiten (gleiches Formular wie die Erfassung, mit allen Feldern ausgeklappt).
3. **Budgets** – pro Ausgaben-Kategorie optionales Monatslimit, Fortschrittsbalken für den laufenden Monat.
4. **Mehr** – Kategorien verwalten (Name, Symbol, Farbe, Reihenfolge, archivieren), wiederkehrende Buchungen verwalten, CSV-Export, Mitglieder (nur Admin), Server & Sync-Status, Face-ID-Sperre an/aus, Abmelden.

### CSV-Export
Lokal aus SwiftData; Zeitraum wählbar (Monat, Jahr, frei). Spalten: Datum, Art, Kategorie, Betrag, Notiz, Bezahlt von. Trennzeichen `;`, Dezimalkomma, UTF-8 mit BOM (Excel-kompatibel in Deutschland). Ausgabe über das Teilen-Menü.

### Allgemein
Swift Charts; Formatierung nach Locale `de_DE`; Dark Mode; Dynamic Type; VoiceOver-Beschriftungen. Sync-Hinweis nur bei Problemen, z. B. „Nicht mit NAS verbunden – 3 Änderungen ausstehend“.

## 8. Fehlerbehandlung

- **Server nicht erreichbar:** lokal normal weiterarbeiten; Zähler ausstehender Änderungen; automatische Wiederholung.
- **Access-Token abgelaufen:** einmalig per Refresh-Token erneuern und Anfrage wiederholen.
- **Refresh-Token ungültig/abgelaufen:** Anmeldebildschirm; lokale ungesendete Daten bleiben erhalten und werden nach dem Login gesendet. Meldet sich ein *anderer* Nutzer an, werden die lokalen Daten zuvor vollständig synchronisiert oder – nach Rückfrage – verworfen.
- **Ungültige Datensätze:** einzeln abgelehnt (Abschnitt 4).
- **Server:** einheitliches Fehlerformat `{ "error": { "code": "…", "message": "…" } }`; unerwartete Fehler werden geloggt und als 500 ohne Interna beantwortet.

## 9. Tests

**Server (Vitest):**
- Unit: Termin-Berechnung wiederkehrender Buchungen (Monatsende, Schaltjahr, Nachholen, `end_date`), Passwort-Hashing, Token-Rotation.
- Integration gegen echtes Postgres (Testcontainers): Sync-Push/Pull, Versionen, Last-Write-Wins, Soft-Delete, Teil-Ablehnung, Idempotenz, `(recurring_rule_id, date)`-Eindeutigkeit, Setup nur einmal möglich, Admin-Rechte.
- OpenAPI-Datei ist aktuell.

**App (Swift Testing):**
- SyncEngine mit Mock-API: Dirty-Handling, Änderung während laufendem Sync, Übernahme von Löschungen, Ablehnungen.
- Summen, Budget-Fortschritt, CSV-Erzeugung, Ziffernblock-Eingabelogik, Sortierung nach Häufigkeit.

**Manueller End-to-End-Test:** zwei Nutzer in zwei Simulatoren; Server stoppen, auf beiden erfassen, Server starten → beide sehen alle Buchungen.

## 10. Betrieb & Deployment

- `docker-compose.yml`:
  - `api` – Node 22, Multi-Arch-Image (amd64/arm64), Port 3000, führt Migrationen beim Start aus.
  - `postgres` – `postgres:17`, Daten auf einem Volume (Ordner auf der NAS).
  - `backup` – täglicher `pg_dump` in einen NAS-Ordner, 30 Tage aufbewahrt.
- Konfiguration über `.env` (`JWT_SECRET`, `POSTGRES_PASSWORD`, `TZ=Europe/Berlin`); `.env.example` im Repo, `.env` in `.gitignore`.
- Betrieb in der Docker-App von UGOS Pro auf der UGREEN-NAS. Update: Image neu bauen, `docker compose up -d`.
- Lokale Entwicklung: dieselbe Compose-Datei auf dem Mac.
- App-Installation: zunächst über Xcode mit kostenlosem Apple-Account (Profil läuft nach 7 Tagen ab, dann neu installieren). Später optional Apple Developer Program (Installation 1 Jahr gültig, TestFlight).
- Repository liegt in OneDrive: `server/node_modules` als „Immer auf diesem Gerät behalten“ markieren; `.gitignore` für `node_modules`, Build-Ordner, `.env`.
