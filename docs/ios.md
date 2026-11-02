# iOS-App: Bauen und Installieren

Die App (SwiftUI, SwiftData, iOS 18+) liegt unter `ios/`. Sie speichert alles lokal und gleicht über `POST /sync` mit dem Server ab; ohne Server bleibt sie voll nutzbar (Hinweis „Nicht mit NAS verbunden – N Änderungen ausstehend“).

## Voraussetzungen

- Xcode (aktuell, mit iOS-Simulator-Runtime), Homebrew
- `brew install xcodegen`
- Server läuft und ist vom Gerät erreichbar (siehe [betrieb.md](betrieb.md)). **Der Server muss mit dem aktuellen Stand von `main` bzw. diesem Branch neu gebaut und gestartet werden** (`docker compose up -d --build`): Die iOS-Arbeit hat die Eingabeverarbeitung des Servers geändert (iOS Task 2); ein älterer Server kann Daten der App ablehnen.

## Projekt erzeugen und bauen

Das Xcode-Projekt wird nicht eingecheckt, sondern aus `ios/project.yml` erzeugt:

```bash
cd ios
xcodegen generate
open Haushaltsbuch.xcodeproj
```

Die API-Schicht wird beim Build vom `swift-openapi-generator`-Plugin erzeugt. Xcode fragt dafür beim ersten Build nach: **„Trust & Enable“** bestätigen. Auf der Kommandozeile stattdessen `-skipPackagePluginValidation` angeben:

```bash
xcodebuild build -project Haushaltsbuch.xcodeproj -scheme Haushaltsbuch \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

## Tests

```bash
ios/scripts/test.sh                       # alle Package-Tests (iPhone-17-Simulator)
ios/scripts/test.sh HaushaltsbuchCoreTests  # Filter
```

`HaushaltsbuchAppUITests` (XCUITest) prüft die App live und braucht einen **laufenden Dev-Server** (`http://localhost:3000`); die Tests gehören nicht zu `test.sh`. Passwörter und Adressen kommen über Umgebungsvariablen mit dem Präfix `TEST_RUNNER_`, z. B. `TEST_RUNNER_HB_PASSWORD=… xcodebuild test -only-testing:HaushaltsbuchAppUITests/OnboardingUITests …` (Details im Kopf der jeweiligen Testdatei; Simulator-Schlüsselbund zuvor mit `xcrun simctl keychain <udid> reset` leeren, wenn der Test eine frische App erwartet).

## Auf eigenen Geräten installieren

1. iPhone/iPad per Kabel verbinden, Entwicklermodus aktivieren (Einstellungen → Datenschutz & Sicherheit → Entwicklermodus).
2. In Xcode: Target **Haushaltsbuch** → Signing & Capabilities → **Team** wählen (Apple-ID unter Xcode → Settings → Accounts anlegen). Die Bundle-ID `de.haushaltsbuch.app` ggf. eindeutig machen. Besser dauerhaft: `DEVELOPMENT_TEAM` in `ios/project.yml` eintragen, damit `xcodegen generate` die Einstellung nicht verliert.
3. Gerät als Ziel wählen, Run. Beim ersten Start auf dem Gerät das Entwicklerprofil unter Einstellungen → Allgemein → VPN & Geräteverwaltung vertrauen.
4. Gültigkeit: Mit **kostenlosem Apple-Account** läuft die Installation **7 Tage**, dann muss neu aus Xcode installiert werden (die lokalen Daten bleiben erhalten, wenn die App nicht vorher gelöscht wurde). Mit dem **Apple Developer Program** (99 €/Jahr) gilt sie **1 Jahr**, und TestFlight ist möglich (Archive → Distribute → App Store Connect).

## Server-Adresse eintragen

Beim ersten Start fragt die App nach der Server-Adresse, danach folgen Einrichtung (erstes Konto, nur beim allerersten Mal) bzw. Anmeldung. Die Adresse ist `http://<Host>:3000` (Port 3000 bzw. `API_PORT` aus der `.env`), je nach Netz:

- **LAN-IP des NAS**, z. B. `http://192.168.1.20:3000` (am besten im Router eine feste Adresse vergeben)
- **`.local`-Name**, z. B. `http://nas.local:3000` (Bonjour)
- **VPN-IP**, z. B. WireGuard/Tailscale `http://100.x.y.z:3000`, wenn man unterwegs ist

Beim ersten Zugriff fragt iOS nach der Berechtigung für das lokale Netzwerk – erlauben. Die App erlaubt unverschlüsseltes HTTP (nur für LAN/VPN gedacht); den Server nie per Port-Forwarding ins Internet stellen. Die Adresse lässt sich später unter **Mehr → Server & Sync** einsehen; Abmelden führt zurück zur Anmeldung. Im iOS-Simulator erreicht `http://localhost:3000` den Server auf dem Mac.

## Face-ID-Sperre

Unter **Mehr** lässt sich die Sperre aktivieren: Beim Zurückkehren in die App (und im App-Umschalter) wird der Inhalt verdeckt, bis Face ID / Touch ID bzw. der Gerätecode bestätigt ist. Im Simulator: Features → Face ID → Enrolled, dann Matching Face auslösen.

## Nach Server-Änderungen: API-Kopie abgleichen

Die App generiert ihren API-Client aus einer Kopie von `server/openapi.json`. Nach jeder Änderung der Server-API:

```bash
ios/scripts/sync-openapi.sh          # Kopie aktualisieren
ios/scripts/sync-openapi.sh --check  # nur prüfen (Exit 1, wenn veraltet)
ios/scripts/test.sh                  # Client neu erzeugen und testen
```

## Sync-Verhalten

Sync läuft beim Start, beim Wechsel in den Vordergrund, 2 s nach einer lokalen Änderung, wenn das Netz wieder da ist, und per Pull-to-Refresh in den Listen. Nach Fehlern wartet die App 5 s, verdoppelt bis max. 300 s; Pull-to-Refresh und „Jetzt synchronisieren“ (Mehr → Server & Sync) umgehen die Wartezeit. Bei gleichzeitigen Änderungen derselben Buchung gilt Last-Write-Wins: Der zuletzt beim Server eintreffende Stand setzt sich auf allen Geräten durch.
