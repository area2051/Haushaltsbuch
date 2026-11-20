#!/bin/sh
# Spielt das neueste Release (höchster Tag vX.Y.Z) ein:
# Backup -> Tag auschecken -> API neu bauen -> /health prüfen.
# Schlägt Build oder Health-Check fehl, läuft wieder das vorherige Image und
# der Git-Stand steht wieder auf dem alten Commit.
# Der Clone bleibt nach einem Update im detached HEAD auf dem Tag (gewollt).
# Es wird nie auf einen Stand gewechselt, der kein Nachfahre von HEAD ist (auch nicht
# mit --force): Migrationen des laufenden Codes können neuer sein.
#
# Aufruf im Repo-Ordner auf dem NAS:  sh ops/update.sh [--force]
#   --force   auch neu bauen, wenn es kein neueres Release gibt
# Umgebungsvariablen (optional):
#   COMPOSE_PROJECT_NAME  Compose-Projektname (sonst vom laufenden Stack gelesen)
#   HB_HEALTH_TIMEOUT     Sekunden für den Health-Check (Standard 90)
set -eu

usage() { echo "Aufruf: sh ops/update.sh [--force]" >&2; }
log() { echo "==> $*"; }
die() { echo "FEHLER: $*" >&2; exit 1; }

force=0
case "${1:-}" in
  "") ;;
  --force) force=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

cd "$(dirname "$0")/.."

HEALTH_TIMEOUT=${HB_HEALTH_TIMEOUT:-90}
if [ -z "${API_PORT:-}" ] && [ -f .env ]; then
  API_PORT=$(sed -n 's/^API_PORT=//p' .env | tail -n 1 | tr -d '\r"')
fi
HEALTH_URL="http://127.0.0.1:${API_PORT:-3000}/health"

# --- Vorprüfungen --------------------------------------------------------------------

git diff --quiet HEAD -- || die "Es gibt lokale Änderungen an versionierten Dateien (git status). Erst aufräumen."

# Projektname des laufenden Stacks. Ein geratener Name würde einen zweiten Stack starten,
# deshalb lieber abbrechen, wenn er nicht eindeutig ist.
if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
  here=$(pwd -P)
  projects=$(docker ps -a --filter "label=com.docker.compose.project.working_dir=$here" \
    --format '{{.Label "com.docker.compose.project"}}' | sed '/^$/d' | sort -u)
  count=$(printf '%s\n' "$projects" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || die "Compose-Projekt für $here nicht eindeutig gefunden (${count} Treffer: $(printf '%s' "$projects" | tr '\n' ' ')). Name setzen, z. B.: COMPOSE_PROJECT_NAME=<name> sh ops/update.sh"
  COMPOSE_PROJECT_NAME=$projects
fi

# Immer die .yml aus dem Repo: UGOS legt ein eigenes docker-compose.yaml an, das Compose
# sonst bevorzugen würde.
compose() { docker compose -f docker-compose.yml -p "$COMPOSE_PROJECT_NAME" "$@"; }

health_ok() {
  if command -v curl > /dev/null 2>&1; then
    curl -fsS -m 5 -o /dev/null "$HEALTH_URL" 2> /dev/null
  else
    wget -q -T 5 -O /dev/null "$HEALTH_URL" 2> /dev/null
  fi
}

wait_healthy() {
  waited=0
  while [ "$waited" -lt "$HEALTH_TIMEOUT" ]; do
    if health_ok; then return 0; fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

# --- Neuer Stand? --------------------------------------------------------------------

log "Hole Releases"
git fetch --quiet --tags --force origin
tag=$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
[ -n "$tag" ] || die "Kein Release (Tag vX.Y.Z) gefunden."
old=$(git rev-parse HEAD)
new=$(git rev-parse "$tag^{commit}")
oldv=$(git describe --tags --exact-match HEAD 2> /dev/null | head -n 1 || true)
[ -n "$oldv" ] || oldv=$(git rev-parse --short HEAD)

# Nie zurück oder zur Seite, auch nicht mit --force.
git merge-base --is-ancestor HEAD "$tag" \
  || die "Release $tag ist nicht neuer als der installierte Stand ($oldv). Kein Update."

if [ "$old" = "$new" ] && [ "$force" -eq 0 ]; then
  log "Bereits aktuell ($tag)."
  exit 0
fi

# Link zum Release, nur für GitHub-Remotes.
release_url=""
repo=$(git remote get-url origin 2> /dev/null | sed -n -e 's#^https://github\.com/\([^/]*/[^/]*\)$#\1#p' -e 's#^git@github\.com:\([^/]*/[^/]*\)$#\1#p' || true)
repo=${repo%.git}
[ -z "$repo" ] || release_url="https://github.com/$repo/releases/tag/$tag"

# --- Update --------------------------------------------------------------------------

log "Backup"
compose exec -T backup sh /backup.sh || die "Backup fehlgeschlagen, Update abgebrochen."

# Image-Name und -ID vom laufenden Container: genau der Name, den Compose beim Neubau
# überschreibt (z. B. <projekt>-api).
image=""
prev=""
cid=$(compose ps -q api || true)
if [ -n "$cid" ]; then
  image=$(docker inspect --format '{{.Config.Image}}' "$cid")
  prev=$(docker inspect --format '{{.Image}}' "$cid")
  docker tag "$prev" "$image:previous"
else
  echo "Hinweis: kein laufender api-Container, ein Rollback ist nicht möglich." >&2
fi

rollback() {
  echo "FEHLER: $1" >&2
  git checkout --quiet --detach "$old"
  if [ -n "$prev" ]; then
    log "Starte das vorherige Image wieder"
    docker tag "$image:previous" "$image"
    compose up -d --no-build api
    if wait_healthy; then
      echo "Der vorherige Stand ($oldv) läuft wieder." >&2
    else
      echo "Auch der vorherige Stand antwortet nicht auf $HEALTH_URL – bitte 'docker compose logs api' prüfen." >&2
    fi
  fi
  echo "Migrationen können schon gelaufen sein. Bei Datenproblemen: Backup von eben zurückspielen (docs/betrieb.md)." >&2
  exit 1
}

log "Aktualisiere $oldv -> $tag"
git checkout --quiet --detach "$tag"

log "Baue und starte die API neu"
compose up -d --build api || rollback "Build/Start der neuen API fehlgeschlagen."

log "Warte auf $HEALTH_URL"
wait_healthy || rollback "Neue API antwortet nach ${HEALTH_TIMEOUT}s nicht auf $HEALTH_URL."

log "Fertig: $oldv -> $tag"
[ -z "$release_url" ] || echo "Release: $release_url"
git log --oneline "$old..$new"
