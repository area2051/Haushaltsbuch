#!/bin/bash
# Kopiert server/openapi.json in das Modul HaushaltsbuchAPI (Eingabe des swift-openapi-generator-Plugins).
# Aufruf: ios/scripts/sync-openapi.sh          → kopieren
#         ios/scripts/sync-openapi.sh --check  → nur prüfen; Exit 1, wenn die Kopie veraltet ist oder fehlt
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/server/openapi.json"
DST="$ROOT/ios/HaushaltsbuchKit/Sources/HaushaltsbuchAPI/openapi.json"

if [ ! -f "$SRC" ]; then
  echo "Fehlt: $SRC" >&2
  exit 2
fi

if [ "${1:-}" = "--check" ]; then
  if [ -f "$DST" ] && cmp -s "$SRC" "$DST"; then
    echo "openapi.json ist aktuell."
    exit 0
  fi
  echo "openapi.json ist veraltet – ios/scripts/sync-openapi.sh ausführen." >&2
  exit 1
fi

cp "$SRC" "$DST"
echo "Kopiert: server/openapi.json → ios/HaushaltsbuchKit/Sources/HaushaltsbuchAPI/openapi.json"
