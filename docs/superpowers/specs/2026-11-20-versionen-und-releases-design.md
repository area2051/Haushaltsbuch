# Versionen und Releases – Kurzentwurf

## Warum
In der App ist nicht zu sehen, welche Version auf dem NAS läuft. Die angezeigte Nummer
soll genau einem GitHub-Release entsprechen, damit man dort nachlesen kann, was drin ist.

## Ziele
- Unter **Mehr → App** steht „Version X.Y.Z“, und zwar die Version, die auf dem NAS läuft.
- Zu jeder Version, die auf dem NAS laufen kann, gibt es ein GitHub-Release `vX.Y.Z`.
- `ops/update.sh` spielt **nur Releases** ein (den höchsten Tag `vX.Y.Z`), nicht `main`.
- Ein Release anzulegen ist ein Klick auf GitHub.

## Keine Ziele
- Keine Anzeige der Version in der iOS-App (vorerst).
- Keine Commit-Hashes in der Anzeige.
- Kein automatisches Release bei jedem Merge.

## Anti-Ziele
- Nummer in der App und Release-Tag dürfen nicht auseinanderlaufen können.
- `ops/update.sh` darf das NAS nie auf einen älteren Stand zurückdrehen, als gerade läuft
  (die Datenbank-Migrationen sind dann schon neuer als der Code).

## Ansätze
- **A – Von Hand:** Nummer im PR erhöhen, danach `gh release create`. Fehleranfällig (zwei
  Dateien plus Tag).
- **B – Workflow „Release“ in GitHub Actions (gewählt):** Actions → Release → Run workflow mit
  *patch/minor/major*; zählt die Nummer hoch, committet auf `main`, setzt den Tag und legt das
  Release an. Nummer und Tag stammen aus demselben Lauf.
- **C – release-please:** Bot-PR mit Changelog; für dieses Projekt zu viel Werkzeug.

## Entscheidungen des Nutzers
- Das NAS aktualisiert nur auf Releases (den neuesten Tag), nicht auf `main`.
- Releases entstehen über den Workflow (B).

## Entscheidungen von Claude (korrigierbar)
- **Quelle der Nummer:** `version` in `server/package.json`; `web/package.json` wird im
  Gleichschritt mitgeführt. Der Server liest sie zur Laufzeit aus `/app/package.json` (liegt
  schon im Image) – kein Build-Argument, kein `.git` im Image nötig.
- **Anzeige:** `GET /health` liefert zusätzlich `version`. Die Web-App fragt die Version beim
  Server ab (nicht ihre eigene Build-Nummer), damit wirklich der laufende NAS-Stand angezeigt
  wird. Zeile unter Mehr → App: „Version 1.0.0“; ohne Verbindung „Version unbekannt“.
- **Erstes Release:** `v1.0.0` (per *major* von 0.1.0), direkt nach dem Merge.
- **Release-Workflow** (`.github/workflows/release.yml`, `workflow_dispatch`, Eingabe
  `bump`: patch/minor/major, `permissions: contents: write`): läuft nur auf `main`;
  `npm version <bump> --no-git-tag-version` in `server/` und `web/` (inklusive
  Lockfiles); Commit „chore(release): vX.Y.Z“, Tag `vX.Y.Z`, Push; `gh release create vX.Y.Z
  --generate-notes`. Bricht ab, wenn der Tag schon existiert oder die beiden Nummern vorher
  nicht gleich sind.
- **CI-Prüfung:** Server- oder Web-Test stellt sicher, dass beide `package.json` dieselbe
  Version haben.
- **`ops/update.sh`:**
  - `git fetch --tags --force`; Ziel = höchster Tag `v[0-9]*` nach Versionssortierung.
  - „Bereits aktuell“, wenn `HEAD` auf diesem Tag-Commit steht (`--force` baut trotzdem neu).
  - Abbruch, wenn der Ziel-Tag nicht Nachfahre von `HEAD` ist (wäre ein Rückschritt);
    das deckt auch den ersten Wechsel von `main` auf Releases ab, solange `main` nicht weiter
    ist als das neueste Release. Mit `--force` lässt sich das nicht umgehen – dann von Hand.
  - Einspielen per `git checkout --detach vX.Y.Z` statt `git merge`; Rollback per
    `git checkout --detach <alter Commit>`.
  - Prüfung „Clone steht auf main“ entfällt; „keine lokalen Änderungen“ bleibt.
  - Ausgabe am Ende: alte → neue Version und Link zum GitHub-Release.
  - Ohne Tags: Abbruch mit Hinweis, erst ein Release anzulegen.
- **Doku:** `docs/betrieb.md` (Update und neuer Abschnitt „Release anlegen“).

## Dem Umsetzer überlassen
Details der Testfälle, Platzierung des Versions-Felds im Health-Schema, Formulierungen.
