# Versionen und Releases – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die laufende Version steht unter Mehr → App, jede Version ist ein GitHub-Release, und `ops/update.sh` spielt nur Releases ein.

**Architecture:** `server/package.json` → `version` ist die einzige Quelle; der Server liest sie zur Laufzeit und liefert sie in `GET /health`; die Web-App zeigt den Wert des Servers. Ein `workflow_dispatch`-Workflow zählt die Nummer hoch, committet, taggt und legt das Release an. `ops/update.sh` checkt den höchsten `v*`-Tag detached aus.

**Tech Stack:** Fastify + Zod + Vitest (server), React + Vitest/Testing Library (web), POSIX sh, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-20-versionen-und-releases-design.md`

## Global Constraints

- Tags heißen `vX.Y.Z`; erster Release `v1.0.0`.
- `server/package.json` und `web/package.json` haben immer dieselbe `version`.
- Anzeige: „Version 1.0.0“; ohne Verbindung „Version unbekannt“. Texte auf Deutsch.
- `ops/update.sh` geht nie auf einen Stand zurück, der nicht Nachfahre von `HEAD` ist – auch nicht mit `--force`.
- `info.version` in der OpenAPI-Beschreibung (`server/src/app.ts:49`) bleibt fest auf `0.1.0`, sonst würde jedes Release `openapi.json`/`schema.d.ts` ändern (Claude-Entscheidung).

## Review Focus

- Erster Lauf auf dem NAS: Clone steht auf `main` genau auf dem Commit von `v1.0.0` → muss „Bereits aktuell“ melden, nicht abbrechen.
- `main` ist weiter als das neueste Release (Merge ohne Release, Clone auf `main`) → Abbruch mit Erklärung, kein Rückschritt.
- Repo ohne Tags → Abbruch mit Hinweis „erst ein Release anlegen“, kein Backup, kein Build.
- Tags in falscher Sortierung (`v1.10.0` vs. `v1.9.0`) → `v1.10.0` gewinnt.
- `/health` antwortet ohne `version` (alter Server während Update) → Web zeigt „Version unbekannt“ statt abzustürzen.

---

### Task 1: Server liefert die Version in `/health`

**Files:**
- Create: `server/src/version.ts`
- Modify: `server/src/setup/routes.ts` (Health-Schema + Handler), `server/openapi.json` (per `npm run openapi`), `web/src/api/schema.d.ts` (per `npm run api` in `web/`), `web/src/test/fakeServer.ts:52`
- Test: `server/test/setup.test.ts`, new `server/test/version.test.ts`

**Interfaces:**
- Produces: `export const APP_VERSION: string` in `server/src/version.ts`; `HealthResponse = { status: 'ok'; setupRequired: boolean; version: string }`; `FakeServer.version = '1.2.3'` (public field) in der Web-Fake.

- [ ] **Step 1: Tests anpassen/schreiben**
  - `setup.test.ts`: beide Health-Tests erwarten zusätzlich `version: APP_VERSION`.
  - `version.test.ts`: `APP_VERSION` gleicht `version` aus `server/package.json` und matcht `/^\d+\.\d+\.\d+$/`; außerdem gleicht `server/package.json` → `version` der `web/package.json` → `version` (beide per `readFileSync` relativ zu `import.meta.url`).
- [ ] **Step 2:** `cd server && npm test -- setup version` → FAIL (Modul fehlt / Feld fehlt).
- [ ] **Step 3:** `version.ts` liest `new URL('../package.json', import.meta.url)` (gilt für `src/` mit tsx und `dist/` im Image, wo `/app/package.json` liegt) und exportiert `APP_VERSION`. Health-Schema um `version: z.string()` erweitern, Handler gibt `APP_VERSION` mit.
- [ ] **Step 4:** `npm run openapi` (server), `npm run api` (web); `FakeServer` liefert `version: this.version` bei `/health`.
- [ ] **Step 5:** `cd server && npm run typecheck && npm test` und `cd web && npm run typecheck && npm test` → PASS (inkl. openapi-/schema-Aktualitätstests).
- [ ] **Step 6: Commit** `feat(server): report app version in /health`

### Task 2: Web zeigt die Version unter Mehr → App

**Files:**
- Modify: `web/src/features/more/More.tsx`
- Test: new `web/src/features/more/More.test.tsx`

**Interfaces:**
- Consumes: `api.health()` aus `useApp()`; `FakeServer.version`, `FakeServer.offline`; `renderSignedIn` aus `web/src/test/renderApp.tsx`.

- [ ] **Step 1: Tests schreiben**
  - `shows the server version`: `renderSignedIn(<More />, { seed: (_, s) => { s.version = '1.2.3' } })` → `await findByText('Version 1.2.3')`.
  - `shows unknown version when health fails`: nach dem Rendern ist der Fake offline bzw. `/health` liefert kein `version` → `await findByText('Version unbekannt')`.
- [ ] **Step 2:** `cd web && npx vitest run src/features/more/More.test.tsx` → FAIL.
- [ ] **Step 3:** In `More` per `useEffect` einmal `api.health()` aufrufen; Zustand `string | null | undefined` (lädt / unbekannt / Wert). Neue `ListRow` in Gruppe „App“ unter der Verbindungszeile, Icon `Info` aus `lucide-react`, Label „Version 1.2.3“ bzw. „Version unbekannt“; während des Ladens „Version …“.
- [ ] **Step 4:** `npm run typecheck && npm test` → PASS.
- [ ] **Step 5: Commit** `feat(web): show the running server version under Mehr`

### Task 3: `ops/update.sh` spielt nur Releases ein

**Files:**
- Modify: `ops/update.sh`, `ops/update.test.sh`

**Interfaces:**
- Git-Aufrufe, auf die die Stubs reagieren: `git fetch --quiet --tags --force origin`, `git tag -l 'v[0-9]*' --sort=-v:refname`, `git rev-parse HEAD`, `git rev-parse <tag>^{commit}`, `git merge-base --is-ancestor HEAD <tag>`, `git checkout --quiet --detach <ref>`, `git diff --quiet HEAD --`, `git log --oneline <alt>..<neu>`.
- `HB_UPDATE_BRANCH` entfällt.

- [ ] **Step 1: Tests umbauen** (Stub-Variablen `STUB_TAGS` = Zeilen, bereits absteigend wie `--sort=-v:refname` es liefert; `STUB_TAG_COMMIT`)
  - entfällt: `wrong_branch_aborts`.
  - `already_current_does_nothing`: HEAD == Tag-Commit → „Bereits aktuell (v1.0.0)“, kein Backup.
  - `no_tags_aborts`: leeres `STUB_TAGS` → Exit 1, Ausgabe enthält „Release“, kein `exec -T backup`.
  - `picks_highest_tag`: `STUB_TAGS="v1.10.0\nv1.9.0"` → `checkout --quiet --detach v1.10.0`.
  - `older_release_aborts_even_with_force`: merge-base-Stub ≠ 0 → Exit 1 mit `--force`, kein Backup, Ausgabe nennt „neuer als“.
  - `success_runs_steps_in_order`: Backup → Tag `:previous` → `checkout --quiet --detach v1.1.0` → `up -d --build api` → curl; Ausgabe enthält alte/neue Version und `https://github.com/area2051/Haushaltsbuch/releases/tag/v1.1.0`.
  - Rollback-Fälle prüfen `checkout --quiet --detach aaa111` statt `reset --keep`.
  - Übrige Fälle (Projektname, Backup-Fehler, lokale Änderungen, kein api-Container, unbekanntes Argument) bleiben, mit neuen Git-Aufrufen.
- [ ] **Step 2:** `sh ops/update.test.sh` → neue Fälle FAIL.
- [ ] **Step 3:** Skript umstellen: Branch-Prüfung raus; Ziel-Tag = erste Zeile von `git tag -l … --sort=-v:refname`; Vergleich über `rev-parse <tag>^{commit}`; Ancestor-Prüfung vor `--force`-Kurzschluss; `checkout --detach` statt `merge --ff-only`; Rollback per `checkout --detach "$old"`. Versionsanzeige: alte Version = `git describe --tags --exact-match HEAD` oder der Kurz-Hash. Release-URL aus `git remote get-url origin` ableiten (`https://github.com/<owner>/<repo>`), bei Nicht-GitHub-Remote weglassen.
- [ ] **Step 4:** `sh ops/update.test.sh` PASS; Shellcheck: `docker run --rm -e LANG=C.UTF-8 -v "$PWD/ops:/mnt:ro" koalaman/shellcheck:v0.10.0 /mnt/update.sh /mnt/update.test.sh` ohne Befund; zusätzlich unter dash: `docker run --rm -v "$PWD/ops:/ops:ro" debian:bookworm-slim sh /ops/update.test.sh`.
- [ ] **Step 5: Commit** `feat(ops): update.sh installs the newest release tag instead of main`

### Task 4: Release-Workflow und Doku

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `docs/betrieb.md` (Abschnitt „Update“ + neuer Abschnitt „Release anlegen“)

- [ ] **Step 1: Workflow schreiben**
  - `on: workflow_dispatch` mit Input `bump` (choice: `patch`, `minor`, `major`; default `patch`); `permissions: contents: write`; Job-Bedingung `github.ref == 'refs/heads/main'`; `concurrency: release`.
  - Schritte: checkout mit `fetch-depth: 0`; setup-node 22; Vorprüfung: Versionen in `server/` und `web/` gleich, sonst Fehler; `npm version "$BUMP" --no-git-tag-version` in `server/` und `web/`; neue Version lesen; Fehler, wenn Tag `v$V` schon existiert (`git rev-parse -q --verify "refs/tags/v$V"`); Commit `chore(release): v$V` als `github-actions[bot]`; `git tag -a "v$V" -m "v$V"`; `git push origin HEAD:main "v$V"`; `gh release create "v$V" --generate-notes --title "v$V"` mit `GH_TOKEN: ${{ github.token }}`.
  - Inputs nur über `env:` in `run:` verwenden (keine `${{ }}`-Interpolation in Shell-Code).
- [ ] **Step 2: Prüfen** mit actionlint: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.7` → ohne Befund.
- [ ] **Step 3: Doku**: Update-Abschnitt sagt jetzt „neuester Release-Tag“, Clone steht danach detached auf dem Tag (normal); erster Umstieg: Clone auf `main` mit `git pull`, Release `v1.0.0` anlegen, dann `sh ops/update.sh` (meldet „Bereits aktuell“ oder spielt ein). „Release anlegen“: GitHub → Actions → Release → Run workflow → patch/minor/major; patch = Fehlerbehebung, minor = neue Funktion, major = großer Umbau.
- [ ] **Step 4: Commit** `ci: release workflow; docs for releases and release-based updates`

### Nach dem Merge (kein Code)

- PR öffnen, CI abwarten, mergen.
- Workflow „Release“ mit `major` starten → `v1.0.0` (0.1.0 → 1.0.0); prüfen: Tag, Release und Commit `chore(release): v1.0.0` auf `main`, beide `package.json` auf `1.0.0`.
