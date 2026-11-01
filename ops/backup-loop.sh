#!/bin/sh
# Läuft täglich um 02:30 (Zeitzone TZ), vor dem Generator um 03:00.
while true; do
  now=$(date +%s)
  next=$(date -d "today 02:30" +%s)
  [ "$next" -le "$now" ] && next=$(date -d "tomorrow 02:30" +%s)
  echo "next backup in $((next - now))s"
  sleep $((next - now))
  /backup.sh || echo "backup failed" >&2
done
