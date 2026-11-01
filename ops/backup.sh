#!/bin/sh
# Erzeugt einen pg_dump (custom format) und löscht Dumps älter als 30 Tage.
set -eu
mkdir -p /backups
file="/backups/haushaltsbuch-$(date +%F).dump"
pg_dump -h postgres -U haushaltsbuch -d haushaltsbuch -Fc -f "$file.tmp"
mv "$file.tmp" "$file"
find /backups -name 'haushaltsbuch-*.dump' -mtime +30 -delete
echo "backup written: $file"
