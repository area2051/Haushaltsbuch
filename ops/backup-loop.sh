#!/bin/sh
# Läuft täglich um 02:30 (Zeitzone TZ), vor dem Generator um 03:00.
# An Tagen, an denen 02:30 nicht existiert (Zeitumstellung), wird 03:30 genutzt.

# target_epoch YYYY-MM-DD -> Epoche von 02:30 (bzw. 03:30) an diesem Tag, leer bei Fehler
target_epoch() {
  date -d "$1 02:30" +%s 2>/dev/null || date -d "$1 03:30" +%s 2>/dev/null || true
}

# delay_from NOW_EPOCH -> Sekunden bis zum nächsten Lauf (immer >= 60)
delay_from() {
  now=$1
  day=$(date -d "@$now" +%F 2>/dev/null || true)
  next=$(target_epoch "$day")
  if [ -z "$next" ] || [ "$next" -le "$now" ]; then
    nextday=$(date -d "$day + 1 day" +%F 2>/dev/null || true)
    next=$(target_epoch "$nextday")
  fi
  if [ -z "$next" ] || [ "$next" -le "$now" ]; then
    echo 3600
    return
  fi
  d=$((next - now))
  [ "$d" -lt 60 ] && d=60
  echo "$d"
}

if [ "${1:-}" = "--delay-from" ]; then
  delay_from "$2"
  exit 0
fi

while true; do
  d=$(delay_from "$(date +%s)")
  echo "next backup in ${d}s"
  sleep "$d"
  sh /backup.sh || echo "backup failed" >&2
  sleep 60
done
