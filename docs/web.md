# Web-App

Die Web-App (`web/`) ist die Browser-Variante des Haushaltsbuchs: gleicher Server, gleiche Daten, gleiche Regeln wie die iOS-App. Gedacht vor allem fürs Handy; am Desktop zeigt die Übersicht zusätzliche Diagramme (12-Monats-Verlauf).

## Aufrufen

`http://<nas-ip>:3000/app/` im Heimnetz oder per VPN. `http://<nas-ip>:3000/` leitet dorthin weiter.

- **Auf dem Handy als App:** In Safari *Teilen → Zum Home-Bildschirm*. Die Seite öffnet sich dann ohne Browserleiste.
- **Ohne Verbindung zur NAS** zeigt die App einen Hinweis mit „Erneut verbinden“; Speichern ist dann gesperrt (keine Offline-Warteschlange, anders als iOS). Scheitert ein Speichern am Netz, bietet die Meldung „Erneut versuchen“ mit denselben Daten an.
- **Tastenkürzel am Desktop:** `N` neue Buchung, Ziffern und ⌫ für den Betrag, ← / → wechseln den Monat, ⌘K / Strg+K öffnet Suche und Befehle (Seiten, Buchungen nach Notiz oder Kategorie).
- **Wiederkehrende Abbuchungen** (Miete, Strom, Grundsteuer …): unter *Mehr → Wiederkehrende Buchungen* oder direkt in der Erfassung über *Details → Wiederholen*. Rhythmus per Auswahl: wöchentlich, alle 2 Wochen, monatlich, vierteljährlich, halbjährlich, jährlich oder „Alle N Monate“ (1–24).
- **Unterkategorien** (z. B. Wohnen · Strom): Hat eine Kategorie Unterkategorien, zeigt die Schnellerfassung nach dem Tipp Chips; ein Tipp auf einen Chip speichert. Die Übersicht klappt Hauptkategorien auf, unter *Mehr → Kategorien* legt „Gehört zu“ die Hauptkategorie fest, der CSV-Export hat die Spalte „Unterkategorie“. Budgets gelten für die Hauptkategorie und zählen ihre Unterkategorien mit.
- **Löschen** von Mitgliedern, Regeln und Kategorien fragt vorher nach; gelöschte Buchungen lassen sich per „Rückgängig“ wiederherstellen.

## Technik

| Thema | Umsetzung |
|---|---|
| Stack | React 19, Vite, TypeScript, Tailwind CSS 4, Recharts, motion, vaul (Bottom-Sheets) |
| API-Typen | `npm run api` erzeugt `src/api/schema.d.ts` aus `server/openapi.json` |
| Daten | `src/sync/store.ts`: In-Memory-Store über `POST /sync`, Speichern optimistisch mit Rücknahme bei Ablehnung |
| Auth | `src/api/client.ts`: Access-Token im Speicher, Refresh-Token in `localStorage`, Erneuerung bei 401 (eine gemeinsame Anfrage) |
| Fachlogik | `src/domain/` (Beträge, Datum, Auswertungen, CSV) – portiert aus `HaushaltsbuchCore` mit denselben Testfällen |
| Symbole | Kategorien speichern SF-Symbol-Namen; `src/domain/icons.ts` ordnet sie Web-Icons zu. Der Editor bietet genau die iOS-Auswahl an. |
| UUIDs | eigene v4-Erzeugung, weil `crypto.randomUUID` unter `http://` (kein Secure Context) fehlt |

Der Server liefert den Build aus `WEB_DIR` (Standard `web-dist`) unter `/app/` aus: gehashte Dateien unter `/app/assets/` mit Langzeit-Cache, `index.html` immer frisch und mit CSP. Unbekannte Pfade ohne Dateiendung liefern die App (Client-Routing), fehlende Dateien eine 404.

## Entwicklung

Zwei Terminals, Server und Vite:

```bash
cd server && DATABASE_URL=postgres://… JWT_SECRET=… npm run dev
```

```bash
cd web && npm install && npm run dev
```

Vite (http://localhost:5173/app/) leitet die API-Pfade an `localhost:3000` weiter. In Claude Code startet `.claude/launch.json` beides (`api`, `web`).

```bash
cd web && npm test          # Vitest (Logik + Komponenten)
cd web && npm run typecheck
cd web && npm run build     # Ausgabe in web/dist
```

Ändert sich die API, zuerst `cd server && npm run openapi`, dann `cd web && npm run api`.

## Grenzen

- Kein Offline-Modus und kein Service Worker (bräuchte HTTPS).
- Keine Sperre per Face ID wie in iOS; wer das Gerät hat, ist angemeldet, bis er sich abmeldet.
