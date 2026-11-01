# Haushaltsbuch Server – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lauffähige TypeScript-API (Setup, Auth, Benutzer, Sync, wiederkehrende Buchungen, OpenAPI) in Docker, deploybar auf die UGREEN-NAS.

**Architecture:** Fastify-App aus einer Factory `buildApp(deps)` mit injizierter DB und Uhr, damit alles per `app.inject()` gegen ein echtes Postgres (Testcontainers) testbar ist. Postgres über Drizzle; eine gemeinsame Sequence `sync_version_seq` liefert die Sync-Versionen. zod-Schemas sind gleichzeitig Validierung und Quelle der `openapi.json`.

**Tech Stack:** Node 22, TypeScript (strict, ESM), Fastify 5, zod 4 + `fastify-type-provider-zod`, `@fastify/swagger`, Drizzle ORM + `postgres` (postgres.js) + drizzle-kit, `@node-rs/argon2`, `jose`, `croner`, pino, Vitest, `@testcontainers/postgresql`.

**Spec:** `docs/superpowers/specs/2026-11-01-haushaltsbuch-design.md` (Plan 2 – iOS-App – folgt separat und konsumiert `server/openapi.json`).

## Global Constraints

- Alle Server-Dateien unter `server/`; Docker-Dateien im Repo-Root bzw. `server/Dockerfile`.
- Node 22, Image multi-arch (amd64/arm64), PostgreSQL 17, Port 3000.
- Beträge: Integer-Cent, `amountCents` ganzzahlig > 0, max 2147483647. Nur EUR.
- `date`-Felder: Kalenderdatum `YYYY-MM-DD` ohne Uhrzeit. „Heute“ immer in `TZ` (Default `Europe/Berlin`) berechnen, nie UTC.
- Sync-Tabellen haben `id uuid`, `version bigint`, `deleted bool`, `created_at`, `updated_at`; jede Änderung bekommt `version = nextval('sync_version_seq')`.
- API-JSON in camelCase, DB-Spalten in snake_case.
- Fehlerformat überall: `{ "error": { "code": string, "message": string } }`; 500 ohne Interna.
- Access-Token 15 Minuten, Refresh-Token 90 Tage mit Rotation; argon2id; Passwort-Mindestlänge 8.
- Login-Sperre: nach 5 Fehlversuchen pro Benutzername 1 Minute.
- Wiederkehrend: täglich 03:00 `Europe/Berlin` + direkt nach Sync mit geänderten Regeln.
- Commit-Messages enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Zwei Geräte bearbeiten offline dieselbe Buchung** → der später eintreffende Push gewinnt, und nach dem nächsten Sync haben beide Geräte denselben Stand. Test in Task 7.
2. **Kategorie wurde auf Gerät A gelöscht, Gerät B bucht offline darauf und synchronisiert** → die Buchung wird angenommen, die Kategorie wird wiederhergestellt als `archived = true, deleted = false` (neue Version). Dadurch gibt es keine verwaisten Buchungen. Eine Löschung einer Kategorie mit aktiven Buchungen wird mit `category_in_use` abgelehnt. Test in Task 7.
3. **Ein bereits rotiertes Refresh-Token wird erneut benutzt** (Replay, doppelter Refresh) → 401 `invalid_refresh_token`; das neue Token bleibt gültig. Test in Task 4.
4. **Kurz nach Mitternacht in Berlin (z. B. 00:30 MEZ = 23:30 UTC des Vortags)** → „heute“ ist das Berliner Datum, eine Monatsmiete zum 1. wird gebucht. Test in Task 8.
5. **Die DB wird aus einem Backup wiederhergestellt; die App sendet `lastVersion` größer als die höchste Server-Version** → die Antwort enthält `fullResync: true` und den kompletten Datenbestand, damit die App ihren Cursor zurücksetzt und nichts übersieht. Test in Task 7.

---

## File Structure

```
server/
  package.json, tsconfig.json, vitest.config.ts, drizzle.config.ts, Dockerfile, .dockerignore
  drizzle/                     generierte SQL-Migrationen (eingecheckt)
  openapi.json                 generiert (Task 9)
  src/
    main.ts                    Einstieg: Config, Migration, App, Scheduler, listen
    app.ts                     buildApp(deps) – registriert Plugins und Routen
    config.ts                  loadConfig(env)
    clock.ts                   Clock, systemClock, todayIn(clock, tz)
    errors.ts                  AppError, errorHandler
    db/schema.ts               Drizzle-Tabellen + sync_version_seq
    db/client.ts               createDb(url), runMigrations(db)
    auth/passwords.ts          hashPassword, verifyPassword
    auth/tokens.ts             Access-/Refresh-Token erzeugen, prüfen, rotieren
    auth/loginLimiter.ts       Fehlversuch-Zähler im Speicher
    auth/plugin.ts             Decorators authenticate / requireAdmin
    auth/routes.ts             /auth/login, /auth/refresh, /auth/logout
    setup/defaultCategories.ts
    setup/routes.ts            /health, /setup
    users/routes.ts            /me, /users
    sync/schemas.ts            zod-Schemas der Sync-Datensätze + Request/Response
    sync/service.ts            applySync(db, userId, request)
    sync/routes.ts             POST /sync
    recurring/dates.ts         reine Terminberechnung
    recurring/generator.ts     generateDueTransactions(db, today)
    recurring/scheduler.ts     startScheduler(db, clock, tz)
    openapi/generate.ts        schreibt openapi.json
  test/
    globalSetup.ts             startet einen Postgres-Container pro Testlauf
    helpers.ts                 createTestApp, setupAdmin, login, MutableClock
    *.test.ts
docker-compose.yml, .env.example, docs/betrieb.md   (Repo-Root)
```

---

### Task 1: Server-Grundgerüst, Config, Fehlerformat, `/health` (ohne DB)

**Files:**
- Create: `server/package.json`, `server/tsconfig.json`, `server/vitest.config.ts`, `server/src/config.ts`, `server/src/clock.ts`, `server/src/errors.ts`, `server/src/app.ts`
- Test: `server/test/config.test.ts`, `server/test/app.test.ts`

**Interfaces:**
- Produces:
  - `type Config = { databaseUrl: string; jwtSecret: string; port: number; timeZone: string }`
  - `loadConfig(env: NodeJS.ProcessEnv): Config` – `DATABASE_URL` Pflicht, `JWT_SECRET` Pflicht und ≥ 32 Zeichen, `PORT` Default 3000, `TZ` Default `Europe/Berlin`; wirft `Error` mit Variablennamen in der Meldung.
  - `interface Clock { now(): Date }`, `systemClock: Clock`, `todayIn(clock: Clock, timeZone: string): string` (`YYYY-MM-DD`, via `Intl.DateTimeFormat('en-CA', { timeZone })`).
  - `class AppError extends Error { constructor(statusCode: number, code: string, message: string) }`
  - `buildApp(deps: { config: Config; db?: Db; clock?: Clock }): Promise<FastifyInstance>` – Zod-Type-Provider gesetzt, Error-Handler registriert. (`db` wird ab Task 2 Pflicht.)

- [ ] **Step 1: Projekt anlegen** – `package.json` (`"type": "module"`, Skripte `build`, `dev` mit `tsx watch src/main.ts`, `test` = `vitest run`, `typecheck` = `tsc --noEmit`, `db:generate` = `drizzle-kit generate`, `openapi` = `tsx src/openapi/generate.ts`), Abhängigkeiten aus dem Tech Stack installieren, `tsconfig.json` strict / `module: NodeNext`.

- [ ] **Step 2: Failing Tests schreiben**

```ts
// test/config.test.ts
test('rejects short JWT_SECRET', () => {
  expect(() => loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/)
})
test('applies defaults', () => {
  const c = loadConfig({ DATABASE_URL: 'postgres://x', JWT_SECRET: 'x'.repeat(32) })
  expect(c).toMatchObject({ port: 3000, timeZone: 'Europe/Berlin' })
})
test('todayIn uses the given time zone', () => {
  const clock = { now: () => new Date('2026-01-31T23:30:00Z') }
  expect(todayIn(clock, 'Europe/Berlin')).toBe('2026-02-01')
})
// test/app.test.ts
test('unknown route returns error envelope', async () => {
  const app = await buildApp({ config })
  const res = await app.inject({ method: 'GET', url: '/nope' })
  expect(res.statusCode).toBe(404)
  expect(res.json()).toEqual({ error: { code: 'not_found', message: expect.any(String) } })
})
test('AppError is rendered with its code', async () => { /* Test-Route wirft new AppError(409,'conflict','x') → 409 + {error:{code:'conflict',message:'x'}} */ })
test('unexpected error returns 500 without internals', async () => { /* Test-Route wirft new Error('secret') → 500, code 'internal', message enthält nicht 'secret' */ })
test('validation error returns 400 validation_failed', async () => { /* Route mit zod-Body, falscher Body → 400, code 'validation_failed' */ })
```

- [ ] **Step 3: Tests laufen lassen** – `cd server && npm test` → FAIL (Module fehlen).
- [ ] **Step 4: Implementieren** – `config.ts`, `clock.ts`, `errors.ts` (`errorHandler` + `notFoundHandler`), `app.ts`.
- [ ] **Step 5: Tests + Typecheck** – `npm test && npm run typecheck` → PASS.
- [ ] **Step 6: Commit** – `git add server && git commit -m "feat(server): scaffold app, config and error envelope"`

---

### Task 2: Datenbankschema, Migrationen, Testinfrastruktur

**Files:**
- Create: `server/src/db/schema.ts`, `server/src/db/client.ts`, `server/drizzle.config.ts`, `server/drizzle/*` (generiert), `server/test/globalSetup.ts`, `server/test/helpers.ts`
- Modify: `server/vitest.config.ts` (globalSetup, `fileParallelism: false`), `server/src/app.ts` (`db` Pflicht)
- Test: `server/test/schema.test.ts`

**Interfaces:**
- Produces:
  - `type Db = PostgresJsDatabase<typeof schema>`; `createDb(url: string): { db: Db; close(): Promise<void> }`; `runMigrations(db: Db): Promise<void>` (Ordner `server/drizzle`).
  - Tabellen-Exporte in `schema.ts`: `users`, `refreshTokens`, `categories`, `transactions`, `budgets`, `recurringRules`; Spalten exakt wie Spec §3. Enums als Postgres-Enums: `kind` (`income`,`expense`), `frequency` (`weekly`,`monthly`,`yearly`). Sync-Tabellen (alle außer `refreshTokens`) mit `version bigint not null default nextval('sync_version_seq')`.
  - Constraints: `users.username` unique; `transactions.category_id`, `budgets.category_id`, `recurring_rules.category_id` → FK `categories.id`; `paid_by` → FK `users.id`; `transactions.recurring_rule_id` → FK `recurring_rules.id`; Unique-Index `(recurring_rule_id, date) WHERE recurring_rule_id IS NOT NULL`; Unique-Index `budgets(category_id) WHERE NOT deleted`; Check `amount_cents > 0`. Index auf `version` je Sync-Tabelle.
  - `helpers.ts`: `createTestApp(opts?: { now?: string }): Promise<{ app: FastifyInstance; db: Db; clock: MutableClock; close(): Promise<void> }>` – leert vorher alle Tabellen (`TRUNCATE … RESTART IDENTITY CASCADE`); `class MutableClock implements Clock { set(iso: string): void; advance(ms: number): void }`.
  - `globalSetup.ts`: startet `PostgreSqlContainer('postgres:17')`, führt Migrationen aus, stellt die URL per `provide('databaseUrl', …)` bereit.

- [ ] **Step 1: Failing Test schreiben**

```ts
test('versions come from one shared sequence', async () => {
  const { db } = await createTestApp()
  const [u] = await db.insert(users).values({ username: 'a', displayName: 'A', passwordHash: 'x', isAdmin: true }).returning()
  const [c] = await db.insert(categories).values({ name: 'X', icon: 'cart', color: '#000000', kind: 'expense', sortOrder: 0 }).returning()
  expect(c.version).toBeGreaterThan(u.version)
})
test('rejects duplicate generated transaction for same rule and date', async () => { /* zweimal gleiche (recurringRuleId,date) einfügen → zweiter Insert wirft (unique) */ })
test('allows a new budget after the old one was soft-deleted', async () => { /* budget deleted=true + neues budget gleiche categoryId → ok */ })
test('rejects amount_cents = 0', async () => { /* Insert wirft (check) */ })
```

- [ ] **Step 2: Test laufen lassen** → FAIL.
- [ ] **Step 3: Schema schreiben, `npm run db:generate`** – erzeugt Migration; die Sequence und die partiellen Indizes ggf. per Custom-SQL-Migration (`drizzle-kit generate --custom`) ergänzen.
- [ ] **Step 4: `client.ts`, `globalSetup.ts`, `helpers.ts` implementieren.**
- [ ] **Step 5: `npm test`** → PASS (Docker muss lokal laufen).
- [ ] **Step 6: Commit** – `git commit -m "feat(server): database schema, migrations and test db"`

---

### Task 3: `/health`, `/setup`, Passwörter, Standard-Kategorien

**Files:**
- Create: `server/src/auth/passwords.ts`, `server/src/setup/defaultCategories.ts`, `server/src/setup/routes.ts`
- Modify: `server/src/app.ts`
- Test: `server/test/setup.test.ts`, `server/test/passwords.test.ts`

**Interfaces:**
- Produces:
  - `hashPassword(plain: string): Promise<string>`, `verifyPassword(hash: string, plain: string): Promise<boolean>` (argon2id).
  - `DEFAULT_CATEGORIES: ReadonlyArray<{ name: string; icon: string; color: string; kind: 'income' | 'expense' }>` – exakt die zehn aus Spec §3 in dieser Reihenfolge; `sortOrder` = Index.
  - `GET /health` → `200 { status: 'ok', setupRequired: boolean }`.
  - `POST /setup` Body `{ username: string (3–32, [a-z0-9._-]), displayName: string (1–50), password: string (≥ 8) }` → `201 { user: UserDto }`; legt Admin + Standard-Kategorien in einer Transaktion an; existiert bereits ein User → `409 setup_already_done`.
  - `type UserDto = { id: string; username: string; displayName: string; isAdmin: boolean }` (zod-Schema `userDto` exportiert, wird in Task 5/7 wiederverwendet).

- [ ] **Step 1: Failing Tests**

```ts
test('health reports setupRequired=true on empty db', …)          // { status:'ok', setupRequired:true }
test('setup creates admin and ten default categories', …)       // 201, isAdmin true, 10 categories, 'Lebensmittel' sortOrder 0
test('setup twice returns 409 setup_already_done', …)
test('concurrent setup calls create exactly one user', …)       // Promise.all zweier POST /setup → genau ein 201, ein 409, users count 1
test('setup rejects password shorter than 8', …)                // 400 validation_failed
test('verifyPassword rejects wrong password', …)
```

- [ ] **Step 2: FAIL bestätigen.**
- [ ] **Step 3: Implementieren** – Parallelität bei Setup: Transaktion mit `pg_advisory_xact_lock(1)` und darin `SELECT count(*) FROM users`.
- [ ] **Step 4: `npm test`** → PASS.
- [ ] **Step 5: Commit** – `git commit -m "feat(server): health and first-run setup"`

---

### Task 4: Login, Refresh mit Rotation, Logout, Login-Sperre, Auth-Plugin

**Files:**
- Create: `server/src/auth/tokens.ts`, `server/src/auth/loginLimiter.ts`, `server/src/auth/plugin.ts`, `server/src/auth/routes.ts`
- Modify: `server/src/app.ts`
- Test: `server/test/auth.test.ts`

**Interfaces:**
- Consumes: `hashPassword`/`verifyPassword` (Task 3), `Clock` (Task 1).
- Produces:
  - `POST /auth/login` Body `{ username, password, deviceName?: string }` → `200 { accessToken: string; refreshToken: string; user: UserDto }`; falsch → `401 invalid_credentials`; gesperrt → `429 too_many_attempts`.
  - `POST /auth/refresh` Body `{ refreshToken }` → `200 { accessToken; refreshToken }`; altes Token wird gelöscht; unbekannt/abgelaufen → `401 invalid_refresh_token`.
  - `POST /auth/logout` (Access-Token) Body `{ refreshToken }` → `204`, löscht das Token.
  - Access-Token: JWT HS256 via `jose`, `sub` = userId, Claim `admin: boolean`, `exp` = 15 min ab `clock.now()`. Refresh-Token: 32 zufällige Bytes base64url, in DB nur SHA-256-Hash, `expires_at` = +90 Tage.
  - Fastify-Decorators: `app.authenticate` (setzt `request.user = { id: string; isAdmin: boolean }`, sonst `401 unauthorized`), `app.requireAdmin` (sonst `403 forbidden`).
  - `createLoginLimiter(clock: Clock): { check(username: string): void /* wirft AppError 429 */; fail(username: string): void; reset(username: string): void }` – 5 Fehlversuche → 60 s gesperrt.

- [ ] **Step 1: Failing Tests**

```ts
test('login returns tokens and user', …)
test('wrong password → 401 invalid_credentials', …)
test('6th attempt within a minute → 429, allowed again after 60s', …)   // clock.advance(60_000)
test('access token expires after 15 minutes', …)                      // clock.advance(15*60_000+1) → GET /me 401
test('refresh rotates: new token works, old token → 401', …)
test('reusing a rotated refresh token keeps the new one valid', …)    // Review Focus 3
test('refresh token expires after 90 days', …)
test('logout revokes the refresh token', …)
test('requireAdmin rejects non-admin with 403', …)                    // über eine Testroute
```

- [ ] **Step 2: FAIL bestätigen.**
- [ ] **Step 3: Implementieren** – jose bekommt die Zeit über `clock.now()` (`setIssuedAt`/`setExpirationTime` mit Sekundenwerten, `jwtVerify(..., { currentDate: clock.now() })`).
- [ ] **Step 4: `npm test`** → PASS.
- [ ] **Step 5: Commit** – `git commit -m "feat(server): JWT auth with rotating refresh tokens"`

---

### Task 5: `/me` und `/users`

**Files:**
- Create: `server/src/users/routes.ts`
- Modify: `server/src/app.ts`
- Test: `server/test/users.test.ts`

**Interfaces:**
- Consumes: `authenticate`, `requireAdmin` (Task 4), `userDto` (Task 3).
- Produces:
  - `GET /me` → `UserDto`. `PATCH /me` Body `{ displayName?: string; currentPassword?: string; newPassword?: string }` – `newPassword` nur mit korrektem `currentPassword`, sonst `400 wrong_password`; Passwortwechsel löscht alle anderen Refresh-Tokens des Users.
  - `GET /users` (Admin) → `UserDto[]`. `POST /users` (Admin) Body wie Setup + `isAdmin?: boolean` → `201 UserDto`; doppelter Username → `409 username_taken`. `PATCH /users/:id` (Admin) Body `{ displayName?; password?; isAdmin? }` → `UserDto`; Entzug des Admin-Rechts beim letzten Admin → `409 last_admin`.
  - Jede Änderung an `users` setzt `version = nextval('sync_version_seq')` und `updated_at = now()`.

- [ ] **Step 1: Failing Tests**

```ts
test('GET /me returns current user', …)
test('PATCH /me changes password only with correct current password', …)
test('changing password revokes other refresh tokens', …)
test('admin creates member who can log in', …)
test('duplicate username → 409 username_taken', …)
test('removing admin from last admin → 409 last_admin', …)
test('member cannot list users (403)', …)
test('user update bumps version', …)
```

- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(server): profile and member management`

---

### Task 6: Terminberechnung wiederkehrender Buchungen (rein)

**Files:**
- Create: `server/src/recurring/dates.ts`
- Test: `server/test/recurring-dates.test.ts`

**Interfaces:**
- Produces:
  - `type Frequency = 'weekly' | 'monthly' | 'yearly'`
  - `nextOccurrence(startDate: string, frequency: Frequency, after: string): string` – nächster Termin **strikt nach** `after`, verankert an `startDate` (nicht am vorigen Termin, damit 31. → 28./29. Feb → 31. März wieder stimmt).
  - `dueDates(rule: { startDate: string; frequency: Frequency; nextDueDate: string; endDate: string | null }, today: string): { dates: string[]; nextDueDate: string }` – alle Termine `nextDueDate <= d <= today` (und `<= endDate`), plus der neue `nextDueDate`.
  - Reine String-Datumsarithmetik (UTC-basiert über `Date.UTC`), keine Zeitzonen.

- [ ] **Step 1: Failing Tests**

```ts
test('monthly on 31st clamps to month end and returns to 31st', () => {
  expect(nextOccurrence('2026-01-31', 'monthly', '2026-01-31')).toBe('2026-02-28')
  expect(nextOccurrence('2026-01-31', 'monthly', '2026-02-28')).toBe('2026-03-31')
})
test('monthly in leap year February', () => expect(nextOccurrence('2028-01-30', 'monthly', '2028-01-30')).toBe('2028-02-29'))
test('yearly Feb 29 → Feb 28 in non-leap year', () => expect(nextOccurrence('2028-02-29', 'yearly', '2028-02-29')).toBe('2029-02-28'))
test('weekly keeps weekday', () => expect(nextOccurrence('2026-11-02', 'weekly', '2026-11-02')).toBe('2026-11-09'))
test('dueDates catches up missed dates', () => {
  expect(dueDates({ startDate: '2026-08-01', frequency: 'monthly', nextDueDate: '2026-09-01', endDate: null }, '2026-11-01'))
    .toEqual({ dates: ['2026-09-01', '2026-10-01', '2026-11-01'], nextDueDate: '2026-12-01' })
})
test('dueDates respects endDate', …)   // endDate '2026-10-15' → nur 09-01, 10-01
test('dueDates returns nothing before start', …)
```

- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS** – **Step 5: Commit** `feat(server): recurring date calculation`

---

### Task 7: Sync-Endpunkt

**Files:**
- Create: `server/src/sync/schemas.ts`, `server/src/sync/service.ts`, `server/src/sync/routes.ts`
- Modify: `server/src/app.ts`
- Test: `server/test/sync.test.ts`

**Interfaces:**
- Consumes: `authenticate` (Task 4), `userDto` (Task 3), Schema (Task 2). Ein Hook `onRulesChanged?: () => Promise<void>` wird in Task 8 belegt.
- Produces (zod-Schemas exportiert, Namen sind die OpenAPI-Komponenten):
  - `CategoryRecord = { id: uuid; deleted: boolean; name: string(1–40); icon: string; color: /^#[0-9A-Fa-f]{6}$/; kind; sortOrder: int; archived: boolean }`
  - `TransactionRecord = { id; deleted; amountCents; kind; categoryId: uuid; date: YYYY-MM-DD; note: string(≤200) | null; paidBy: uuid; recurringRuleId: uuid | null }`
  - `BudgetRecord = { id; deleted; categoryId; monthlyLimitCents: int > 0 }`
  - `RecurringRuleRecord = { id; deleted; amountCents; kind; categoryId; note; paidBy; frequency; startDate; endDate: string | null }` – `nextDueDate` setzt nur der Server (bei neuer Regel = `startDate`; bei geändertem `startDate`/`frequency` neu berechnet als erster Termin `>= heute`); in der Antwort enthalten.
  - Antwort-Datensätze zusätzlich `version: number`. `UserRecord = UserDto & { version: number }`.
  - `SyncRequest = { lastVersion: int >= 0; changes: { categories?: CategoryRecord[]; transactions?: …; budgets?: …; recurringRules?: … } }` – Datensätze im Request werden **einzeln** geparst (`z.unknown()` im Array, Validierung im Service), damit ein kaputter Datensatz nicht den ganzen Request kippt.
  - `SyncResponse = { currentVersion: number; fullResync: boolean; changes: { categories; transactions; budgets; recurringRules; users }; rejected: { table: string; id: string | null; reason: string }[] }`
  - `applySync(db: Db, userId: string, req: SyncRequest, today: string): Promise<{ response: SyncResponse; rulesChanged: boolean }>`

Ablauf in `applySync` (eine Transaktion, zuerst `pg_advisory_xact_lock(2)`):
1. Reihenfolge: categories → recurringRules → transactions → budgets (Fremdschlüssel innerhalb eines Pushes auflösbar).
2. Jeder Datensatz: zod-Parse; Fehler → `rejected` mit `reason` = erste zod-Meldung. Upsert per `ON CONFLICT (id) DO UPDATE` aller Felder + `version = nextval(...)`, `updated_at = now()`, jeweils in einem Savepoint (`tx.transaction`), DB-Fehler (FK, Unique) → `rejected` mit `reason` = `foreign_key_violation` | `unique_violation`.
3. Kategorie mit `deleted: true`, auf die nicht gelöschte Buchungen oder Regeln zeigen → `rejected` `category_in_use`.
4. Buchung/Regel/Budget auf eine gelöschte Kategorie → Kategorie auf `deleted=false, archived=true` setzen (neue Version), Datensatz annehmen (Review Focus 2).
5. `lastVersion > max(version)` über alle Sync-Tabellen → `fullResync: true`, Pull ab 0.
6. Pull: alle Datensätze aller Sync-Tabellen mit `version > lastVersion` (bzw. alle bei fullResync), Users als `UserRecord`. `currentVersion` = höchste Version im System.

- [ ] **Step 1: Failing Tests**

```ts
test('initial sync returns default categories and users', …)               // lastVersion 0 → 10 categories, 1 user, currentVersion > 0
test('pushed transaction is returned to another user', …)                  // A push, B sync(0) enthält Buchung mit paidBy A
test('only changes after lastVersion are returned', …)
test('repeating the same push creates no duplicates', …)                   // gleicher Request 2× → 1 Zeile
test('last write wins and both devices converge', …)                       // Review Focus 1: A und B ändern note offline; B pusht nach A → beide sehen B's note
test('soft delete is propagated', …)                                       // deleted:true kommt bei anderem Gerät an
test('invalid record is rejected alone', …)                                // amountCents 0 + gültige Buchung → 1 rejected, 1 gespeichert
test('unknown categoryId → rejected foreign_key_violation', …)
test('deleting a category in use → rejected category_in_use', …)
test('booking on a deleted category restores it as archived', …)          // Review Focus 2
test('lastVersion ahead of server → fullResync with all data', …)          // Review Focus 5
test('second budget for same category → rejected unique_violation', …)
test('new recurring rule gets nextDueDate = startDate', …)
test('sync without token → 401', …)
```

- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Commit** – `git commit -m "feat(server): bidirectional sync endpoint"`

---

### Task 8: Erzeugung wiederkehrender Buchungen + Scheduler

**Files:**
- Create: `server/src/recurring/generator.ts`, `server/src/recurring/scheduler.ts`
- Modify: `server/src/sync/routes.ts` (nach Sync mit `rulesChanged` Generator aufrufen, **vor** dem Senden der Antwort und mit anschließendem erneutem Pull, damit die neuen Buchungen in derselben Antwort stehen)
- Test: `server/test/recurring-generator.test.ts`

**Interfaces:**
- Consumes: `dueDates` (Task 6), `todayIn` (Task 1), Schema (Task 2).
- Produces:
  - `generateDueTransactions(db: Db, today: string): Promise<number>` – für jede nicht gelöschte Regel `dueDates(...)`, Buchungen `{ id: randomUUID(), recurringRuleId, date, amountCents, kind, categoryId, note, paidBy }` per `INSERT … ON CONFLICT DO NOTHING` auf den Unique-Index, `next_due_date` aktualisieren (Regel bekommt neue Version); gibt Anzahl neuer Buchungen zurück. Läuft unter `pg_advisory_xact_lock(2)` (gleicher Lock wie Sync).
  - `startScheduler(db: Db, clock: Clock, timeZone: string): { stop(): void }` – `croner` mit `'0 3 * * *'` und `timezone`; führt außerdem einmal beim Start aus (Nachholen nach Ausfall).

- [ ] **Step 1: Failing Tests**

```ts
test('generates due transactions and advances nextDueDate', …)
test('running twice on the same day creates nothing new', …)
test('catches up missed months after downtime', …)
test('a deleted generated transaction is not recreated', …)          // Buchung deleted=true, Generator erneut → count bleibt
test('uses Berlin date shortly after midnight', …)                   // Review Focus 4: clock 2026-10-31T23:30:00Z, Regel startDate 2026-11-01 → todayIn → 1 Buchung
test('sync creating a rule returns its generated transactions in the same response', …)
test('deleted rule generates nothing', …)
```

- [ ] **Step 2: FAIL** – **Step 3: Implementieren** – **Step 4: PASS**
- [ ] **Step 5: Commit** – `git commit -m "feat(server): recurring transaction generator and scheduler"`

---

### Task 9: OpenAPI-Spezifikation

**Files:**
- Create: `server/src/openapi/generate.ts`, `server/openapi.json` (generiert)
- Modify: `server/src/app.ts` (`@fastify/swagger` mit `jsonSchemaTransform` aus `fastify-type-provider-zod`, Bearer-Security-Schema; Routen bekommen `operationId`s)
- Test: `server/test/openapi.test.ts`

**Interfaces:**
- Produces: `server/openapi.json` (OpenAPI 3.1) mit `operationId`s `getHealth`, `setup`, `login`, `refresh`, `logout`, `getMe`, `updateMe`, `listUsers`, `createUser`, `updateUser`, `sync`; benannte Komponenten für alle Record-Schemas aus Task 7 und `UserDto`, `ErrorResponse`. `npm run openapi` schreibt die Datei (sortierte Keys, 2 Spaces).
- Plan 2 (iOS) generiert daraus den Swift-Client – die `operationId`s sind dort die Methodennamen.

- [ ] **Step 1: Failing Tests**

```ts
test('checked-in openapi.json is up to date', async () => {
  const app = await buildApp(testDeps); await app.ready()
  expect(JSON.parse(readFileSync('openapi.json', 'utf8'))).toEqual(stableSpec(app.swagger()))
})
test('every route has an operationId', …)
test('SyncResponse component exists', …)
```

- [ ] **Step 2: FAIL** – **Step 3: Implementieren, `npm run openapi`** – **Step 4: PASS**
- [ ] **Step 5: Commit** – `git commit -m "feat(server): generate OpenAPI spec"`

---

### Task 10: Einstiegspunkt, Docker, Backup, Betriebsdoku

**Files:**
- Create: `server/src/main.ts`, `server/Dockerfile`, `server/.dockerignore`, `docker-compose.yml`, `.env.example`, `docs/betrieb.md`

**Interfaces:**
- Consumes: `loadConfig`, `createDb`, `runMigrations`, `buildApp`, `startScheduler`.
- Produces:
  - `main.ts`: Config laden → Migrationen → App bauen → Scheduler starten → `listen({ host: '0.0.0.0', port })`; bei `SIGTERM` Scheduler stoppen, App und DB schließen.
  - `Dockerfile`: Multi-Stage auf `node:22-slim`, `npm ci`, `npm run build`, Laufzeit nur `dist/`, `drizzle/`, Prod-Abhängigkeiten, User `node`, `HEALTHCHECK` auf `/health`.
  - `docker-compose.yml`: `postgres` (`postgres:17`, Volume `./data/postgres`, Healthcheck `pg_isready`), `api` (Build `./server`, `depends_on: postgres: condition: service_healthy`, Port `3000:3000`, `restart: unless-stopped`), `backup` (`postgres:17`, Schleife: täglich `pg_dump -Fc` nach `./backups/haushaltsbuch-YYYY-MM-DD.dump`, Dateien älter als 30 Tage löschen). Alle mit `TZ=${TZ:-Europe/Berlin}`.
  - `.env.example`: `POSTGRES_PASSWORD=`, `JWT_SECRET=` (Hinweis: `openssl rand -base64 48`), `TZ=Europe/Berlin`; `DATABASE_URL` setzt die Compose-Datei selbst.
  - `docs/betrieb.md`: lokaler Start, Multi-Arch-Build (`docker buildx build --platform linux/amd64,linux/arm64`), Deployment in der UGOS-Pro-Docker-App, Update, Backup wiederherstellen (`pg_restore`), erster Setup-Aufruf per curl.

- [ ] **Step 1: Dateien anlegen.**
- [ ] **Step 2: Stack starten** – `cp .env.example .env` (Werte setzen), `docker compose up -d --build` → alle drei Container `healthy`/`running`.
- [ ] **Step 3: Smoke-Test**

```bash
curl -s localhost:3000/health                      # {"status":"ok","setupRequired":true}
curl -s -XPOST localhost:3000/setup -H 'content-type: application/json' \
  -d '{"username":"admin","displayName":"Admin","password":"geheim123"}'   # 201
curl -s -XPOST localhost:3000/auth/login -H 'content-type: application/json' \
  -d '{"username":"admin","password":"geheim123"}'                        # accessToken …
```
Danach `POST /sync` mit `{"lastVersion":0,"changes":{}}` und Bearer-Token → 10 Kategorien.

- [ ] **Step 4: Neustart-Test** – `docker compose restart api` → Daten bleiben, `setupRequired:false`. Backup-Container einmal manuell auslösen (`docker compose exec backup …`) → Dump-Datei vorhanden.
- [ ] **Step 5: Gesamtprüfung** – `cd server && npm test && npm run typecheck` → PASS.
- [ ] **Step 6: Commit** – `git commit -m "feat: docker deployment, backups and operations guide"`
