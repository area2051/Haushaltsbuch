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

Ist Port 3000 belegt, in `.env` `API_PORT=3001` setzen. Daten liegen in `./data/postgres`, Backups in `./backups` (beide nicht im Git).

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

Migrationen laufen beim Start der API automatisch. Daten bleiben im Volume `./data/postgres` erhalten.

## Backup

Der Container `backup` erstellt täglich um 02:30 (Zeitzone `TZ`) `./backups/haushaltsbuch-YYYY-MM-DD.dump` (`pg_dump -Fc`) und löscht Dumps älter als 30 Tage. Manuell auslösen:

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
# 4. Wieder starten
docker compose start api backup
```

Zusätzlich sollte `./backups` regelmäßig auf ein anderes Medium kopiert werden.
