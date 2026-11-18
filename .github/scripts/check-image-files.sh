#!/bin/sh
# Runs inside the API image as its runtime user (node) and fails when a file the
# server needs at runtime is unreadable. See server/Dockerfile (chmod before USER).
fail=0
for p in /app/package.json /app/drizzle/meta/_journal.json /app/dist/main.js /app/web-dist/index.html; do
  if cat "$p" > /dev/null 2>&1; then echo "ok   $p"; else echo "FAIL $p"; fail=1; fi
done
for d in /app/drizzle /app/drizzle/meta /app/web-dist/assets; do
  if ls "$d" > /dev/null 2>&1; then echo "ok   $d/"; else echo "FAIL $d/"; fail=1; fi
done
for f in /app/drizzle/*.sql; do
  if ! cat "$f" > /dev/null 2>&1; then echo "FAIL $f"; fail=1; fi
done
exit $fail
