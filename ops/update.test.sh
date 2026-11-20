#!/bin/sh
# Tests für ops/update.sh ohne echtes Git/Docker: git, docker, curl und sleep werden
# durch Stubs ersetzt, die jeden Aufruf in $T/calls protokollieren.
# Aufruf: sh ops/update.test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/update.sh"
fails=0
passes=0

# --- Stubs ---------------------------------------------------------------------------

make_stubs() {
  mkdir -p "$T/bin" "$T/repo/ops" "$T/state"
  cp "$SCRIPT" "$T/repo/ops/update.sh"
  : > "$T/repo/docker-compose.yml"
  echo "API_PORT=3999" > "$T/repo/.env"
  echo "$STUB_HEAD" > "$T/state/head"

  cat > "$T/bin/git" <<'EOF'
#!/bin/sh
echo "git $*" >> "$T/calls"
case "$*" in
  "rev-parse --abbrev-ref HEAD") echo "$STUB_BRANCH" ;;
  "rev-parse HEAD") cat "$T/state/head" ;;
  "rev-parse origin/"*) echo "$STUB_REMOTE" ;;
  "diff --quiet HEAD"*) exit "$STUB_DIRTY" ;;
  "fetch"*) exit 0 ;;
  "merge-base --is-ancestor"*) exit "$STUB_DIVERGED" ;;
  "merge --ff-only"*) echo "$STUB_REMOTE" > "$T/state/head" ;;
  "reset --keep "*) echo "$3" > "$T/state/head" ;;
  "log"*) echo "abc123 neue Funktion" ;;
  *) echo "unerwarteter git-Aufruf: $*" >&2; exit 99 ;;
esac
EOF

  cat > "$T/bin/docker" <<'EOF'
#!/bin/sh
echo "docker $*" >> "$T/calls"
case "$*" in
  "ps "*) printf '%s' "$STUB_PROJECTS" ;;
  *" exec -T backup "*) exit "$STUB_BACKUP_FAIL" ;;
  *" ps -q api") [ "$STUB_NO_API" = 1 ] || echo "cid1" ;;
  "inspect --format {{.Image}} cid1") echo "sha256:old" ;;
  "inspect --format {{.Config.Image}} cid1") echo "hb-api" ;;
  "tag "*) exit 0 ;;
  *" up -d --build api") exit "$STUB_BUILD_FAIL" ;;
  *" up -d --no-build api") touch "$T/state/rolled_back" ;;
  *) echo "unerwarteter docker-Aufruf: $*" >&2; exit 99 ;;
esac
EOF

  cat > "$T/bin/curl" <<'EOF'
#!/bin/sh
echo "curl $*" >> "$T/calls"
case "$STUB_HEALTH" in
  ok) exit 0 ;;
  fail) exit 7 ;;
  new-fails) [ -f "$T/state/rolled_back" ] && exit 0; exit 7 ;;
esac
EOF

  printf '#!/bin/sh\nexit 0\n' > "$T/bin/sleep"
  chmod +x "$T/bin/git" "$T/bin/docker" "$T/bin/curl" "$T/bin/sleep"
  : > "$T/calls"
}

# Standardwerte: alles ok, ein Commit neuer auf origin/main.
defaults() {
  STUB_BRANCH=main STUB_HEAD=aaa111 STUB_REMOTE=bbb222 STUB_DIRTY=0 STUB_DIVERGED=0
  STUB_BACKUP_FAIL=0 STUB_BUILD_FAIL=0 STUB_HEALTH=ok STUB_NO_API=0
  STUB_PROJECTS="haushaltsbuch
"
}

run_update() {
  make_stubs
  out=$(cd "$T" && env PATH="$T/bin:$PATH" T="$T" STUB_BRANCH="$STUB_BRANCH" STUB_HEAD="$STUB_HEAD" \
    STUB_REMOTE="$STUB_REMOTE" STUB_DIRTY="$STUB_DIRTY" STUB_DIVERGED="$STUB_DIVERGED" \
    STUB_BACKUP_FAIL="$STUB_BACKUP_FAIL" STUB_BUILD_FAIL="$STUB_BUILD_FAIL" STUB_HEALTH="$STUB_HEALTH" \
    STUB_PROJECTS="$STUB_PROJECTS" STUB_NO_API="$STUB_NO_API" HB_HEALTH_TIMEOUT=6 COMPOSE_PROJECT_NAME="${FORCE_PROJECT:-}" \
    sh "$T/repo/ops/update.sh" "$@" 2>&1)
  code=$?
}

# --- Assertions ----------------------------------------------------------------------

fail() { echo "  FAIL: $*"; failed=1; }
assert_exit() { [ "$code" -eq "$1" ] || fail "Exit $code statt $1"; }
assert_called() { grep -qF -- "$1" "$T/calls" || fail "nicht aufgerufen: $1"; }
assert_not_called() { ! grep -qF -- "$1" "$T/calls" || fail "unerwartet aufgerufen: $1"; }
assert_output() { case "$out" in *"$1"*) ;; *) fail "Ausgabe enthält nicht: $1";; esac; }
# assert_order A B: erster Aufruf mit A kommt vor dem ersten mit B
assert_order() {
  a=$(grep -nF -- "$1" "$T/calls" | head -1 | cut -d: -f1)
  b=$(grep -nF -- "$2" "$T/calls" | head -1 | cut -d: -f1)
  if [ -z "$a" ] || [ -z "$b" ] || [ "$a" -ge "$b" ]; then fail "Reihenfolge: '$1' vor '$2'"; fi
}

run_case() {
  name=$1
  T=$(mktemp -d)
  failed=0
  defaults
  FORCE_PROJECT=
  "$name"
  if [ "$failed" -eq 0 ]; then
    passes=$((passes + 1)); echo "ok   $name"
  else
    fails=$((fails + 1)); echo "FAIL $name"; echo "$out" | sed 's/^/     | /'
  fi
  rm -rf "$T"
}

# --- Fälle ---------------------------------------------------------------------------

already_current_does_nothing() {
  STUB_REMOTE=aaa111
  run_update
  assert_exit 0
  assert_output "Bereits aktuell"
  assert_not_called "exec -T backup"
  assert_not_called "up -d"
}

force_rebuilds_even_when_current() {
  STUB_REMOTE=aaa111
  run_update --force
  assert_exit 0
  assert_called "up -d --build api"
}

wrong_branch_aborts() {
  STUB_BRANCH=feat/web-app
  run_update
  assert_exit 1
  assert_output "git switch main"
  assert_not_called "fetch"
  assert_not_called "up -d"
}

local_changes_abort() {
  STUB_DIRTY=1
  run_update
  assert_exit 1
  assert_output "lokale Änderungen"
  assert_not_called "up -d"
}

diverged_history_aborts_before_backup() {
  STUB_DIVERGED=1
  run_update
  assert_exit 1
  assert_not_called "exec -T backup"
  assert_not_called "merge --ff-only"
}

unknown_project_aborts() {
  STUB_PROJECTS=""
  run_update
  assert_exit 1
  assert_output "COMPOSE_PROJECT_NAME"
  assert_not_called "up -d"
}

ambiguous_project_aborts() {
  STUB_PROJECTS="haushaltsbuch
haushaltsbuch-alt
"
  run_update
  assert_exit 1
  assert_output "COMPOSE_PROJECT_NAME"
}

project_name_from_env_skips_detection() {
  FORCE_PROJECT=meinprojekt
  run_update
  assert_exit 0
  assert_not_called "docker ps "
  assert_called "-p meinprojekt"
}

success_runs_steps_in_order() {
  run_update
  assert_exit 0
  assert_called "docker compose -f docker-compose.yml -p haushaltsbuch"
  assert_order "exec -T backup sh /backup.sh" "tag sha256:old hb-api:previous"
  assert_order "tag sha256:old hb-api:previous" "merge --ff-only"
  assert_order "merge --ff-only" "up -d --build api"
  assert_order "up -d --build api" "curl"
  assert_called "http://127.0.0.1:3999/health"
  assert_not_called "up -d --no-build"
  assert_output "aaa111"
  assert_output "bbb222"
  assert_output "abc123 neue Funktion"
}

backup_failure_stops_before_pull() {
  STUB_BACKUP_FAIL=1
  run_update
  assert_exit 1
  assert_output "Backup"
  assert_not_called "merge --ff-only"
  assert_not_called "up -d"
}

build_failure_rolls_back() {
  STUB_BUILD_FAIL=1
  run_update
  assert_exit 1
  assert_called "tag hb-api:previous hb-api"
  assert_called "up -d --no-build api"
  assert_called "reset --keep aaa111"
  assert_output "vorherige"
}

health_failure_rolls_back() {
  STUB_HEALTH=new-fails
  run_update
  assert_exit 1
  assert_order "up -d --build api" "up -d --no-build api"
  assert_called "reset --keep aaa111"
  assert_output "Backup"
}

unknown_argument_is_rejected() {
  run_update --bogus
  assert_exit 2
  assert_not_called "fetch"
}

no_running_api_updates_without_rollback_tag() {
  STUB_NO_API=1
  run_update
  assert_exit 0
  assert_output "kein laufender api-Container"
  assert_not_called "docker tag"
  assert_called "up -d --build api"
}

build_failure_without_previous_image_still_resets_git() {
  STUB_NO_API=1 STUB_BUILD_FAIL=1
  run_update
  assert_exit 1
  assert_called "reset --keep aaa111"
  assert_not_called "up -d --no-build"
}

for c in no_running_api_updates_without_rollback_tag build_failure_without_previous_image_still_resets_git already_current_does_nothing force_rebuilds_even_when_current wrong_branch_aborts \
  local_changes_abort diverged_history_aborts_before_backup unknown_project_aborts \
  ambiguous_project_aborts project_name_from_env_skips_detection success_runs_steps_in_order \
  backup_failure_stops_before_pull build_failure_rolls_back health_failure_rolls_back \
  unknown_argument_is_rejected; do
  run_case "$c"
done

echo "$passes ok, $fails fehlgeschlagen"
[ "$fails" -eq 0 ]
