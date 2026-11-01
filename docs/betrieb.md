# Betrieb

Der Server läuft per Docker Compose mit drei Containern: `postgres`, `api` und `backup`.

**Sicherheit:** Die API ist nur im LAN oder per VPN erreichbar. Port 3000 niemals im Router freigeben (kein Port-Forwarding).

## Lokaler Start

```bash
cp .env.example .env
# POSTGRES_PASSWORD (URL-sicher, nur Hex/Alphanumerisch, kein $) und JWT_SECRET erzeugen:
openssl rand -hex 32       # POSTGRES_PASSWORD
openssl rand -base64 48    # JWT_SECRET
docker compose up -d --build
curl -s localhost:3000/health     # {"status":"ok","setupRequired":true}
```

Ist Port 3000 belegt, in `.env` `API_PORT=3001` setzen. Daten liegen in `${DATA_DIR}/postgres` (Standard `./data/postgres`), Backups in `${BACKUP_DIR}` (Standard `./backups`); beide nicht im Git.

**Mac (Repo liegt in OneDrive):** `DATA_DIR` und `BACKUP_DIR` in `.env` auf Ordner **außerhalb** von OneDrive setzen, z. B. `DATA_DIR=/Users/<name>/haushaltsbuch-data` und `BACKUP_DIR=/Users/<name>/haushaltsbuch-backups` (absolute Pfade). Eine Postgres-Datenbank in einem synchronisierten Ordner kann durch den Sync-Client beschädigt werden. Auf dem NAS reichen die Standardwerte.

## Erster Setup-Aufruf

Einmalig den Admin-Benutzer anlegen (danach liefert `/health` `setupRequired:false`):

```bash
curl -s -XPOST http://<nas-ip>:3000/setup -H 'content-type: application/json' \
  -d '{"username":"admin","displayName":"Admin","password":"<sicheres-passwort>"}'
```

## Multi-Arch-Build

Das Image läuft auf `node:22-slim` (Debian/glibc, wegen `@node-rs/argon2`). Für NAS (amd64) und Apple Silicon (arm64):

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t <registry>/haushaltsbuch-api:latest --push server
```

Wird kein Registry-Image genutzt, baut die UGOS-Maschine selbst (`build: ./server` in der Compose-Datei).

## Deployment auf dem UGREEN NAS (UGOS Pro)

1. Projektordner (`docker-compose.yml`, `server/`, `ops/`, `.env`) auf das NAS kopieren, z. B. nach `/volume1/docker/haushaltsbuch`.
2. In der UGOS-Pro-Docker-App unter *Projekt* ein neues Projekt anlegen, den Ordner als Pfad wählen und die `docker-compose.yml` verwenden.
3. `.env` im Projektordner mit eigenen Werten befüllen (`POSTGRES_PASSWORD`, `JWT_SECRET`, `TZ`).
4. Projekt starten; alle drei Container sollten laufen, `api` und `postgres` als `healthy`.
5. Setup-Aufruf per curl ausführen (siehe oben).

## Update

```bash
git pull            # bzw. neuen Stand auf das NAS kopieren
docker compose up -d --build
```

Migrationen laufen beim Start der API automatisch. Daten bleiben in `${DATA_DIR}/postgres` erhalten.

## Backup

Der Container `backup` erstellt täglich um 02:30 (Zeitzone `TZ`) `${BACKUP_DIR}/haushaltsbuch-YYYY-MM-DD.dump` (`pg_dump -Fc`) und löscht Dumps älter als 30 Tage. Manuell auslösen:

```bash
docker compose exec backup sh /backup.sh
```

## Backup wiederherstellen

```bash
# 1. Dump prüfen, bevor etwas gelöscht wird (muss den Inhalt auflisten, ohne Fehler):
docker compose exec -T postgres pg_restore -l < backups/haushaltsbuch-YYYY-MM-DD.dump | head
# 2. API und Backup-Container anhalten
docker compose stop api backup
# 3. Datenbank neu anlegen und einspielen
docker compose exec -T postgres dropdb -U haushaltsbuch haushaltsbuch
docker compose exec -T postgres createdb -U haushaltsbuch haushaltsbuch
docker compose exec -T postgres pg_restore -U haushaltsbuch -d haushaltsbuch < backups/haushaltsbuch-YYYY-MM-DD.dump
# 4. Sync-Versionen über den alten Stand heben und Resync-Grenze setzen (Erklärung unten)
docker compose exec -T postgres psql -U haushaltsbuch -d haushaltsbuch -v ON_ERROR_STOP=1 <<'SQL'
UPDATE sync_meta SET resync_floor = setval('sync_version_seq', COALESCE(GREATEST(
  (SELECT max(version) FROM users),
  (SELECT max(version) FROM categories),
  (SELECT max(version) FROM transactions),
  (SELECT max(version) FROM budgets),
  (SELECT max(version) FROM recurring_rules),
  (SELECT last_value FROM sync_version_seq)
), 0) + 1000000);
SELECT resync_floor FROM sync_meta;
SQL
# 5. Wieder starten
docker compose start api backup
```

(Bei abweichendem `BACKUP_DIR` den Pfad in den Befehlen entsprechend anpassen.)

**Warum Schritt 4 Pflicht ist:** Jede Änderung bekommt eine fortlaufende Sync-Version; Geräte merken sich die zuletzt gesehene (`lastVersion`). Nach dem Einspielen läge die Versionsfolge wieder beim Stand des Backups, neue Änderungen bekämen also Versionsnummern, die ein Gerät schon gesehen hat – das Gerät würde diese Datensätze dauerhaft überspringen. Schritt 4 setzt die Sequenz auf das bisherige Maximum aller Sync-Tabellen plus 1.000.000 und speichert diesen Wert als `resync_floor` (die zweite Abfrage zeigt ihn an; er muss größer als 0 sein).

**Was die Apps danach tun:** Jedes Gerät, dessen `lastVersion` unter `resync_floor` liegt (also jedes, das vor der Wiederherstellung synchronisiert hat), bekommt beim nächsten Sync `fullResync: true` mit dem vollständigen Datenbestand und ersetzt seinen lokalen Stand damit. Noch nicht hochgeladene lokale Änderungen schickt es dabei wie gewohnt mit; sie bleiben erhalten. Änderungen, die nach dem Backup, aber vor der Wiederherstellung bereits auf dem Server waren, sind verloren (auch auf den Geräten, da diese den Serverstand übernehmen) und müssen von Hand nachgetragen werden.

Schlägt Schritt 4 mit `relation "sync_meta" does not exist` fehl, stammt der Dump von einer Version vor dieser Tabelle: dann zuerst nur `docker compose start api` (legt die Tabelle per Migration an), sofort `docker compose stop api` und Schritt 4 wiederholen.

Zusätzlich sollte `./backups` regelmäßig auf ein anderes Medium kopiert werden.
