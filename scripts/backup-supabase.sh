#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"
backup_dir="${YAMO_BACKUP_DIR:-./backups}"
retention_days="${YAMO_BACKUP_RETENTION_DAYS:-14}"
mkdir -p "$backup_dir"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="$backup_dir/yamo_${stamp}.dump"
pg_dump --format=custom --no-owner --no-acl --file="$target" "$SUPABASE_DB_URL"
sha256sum "$target" > "$target.sha256"
find "$backup_dir" -type f -name 'yamo_*.dump*' -mtime "+$retention_days" -delete
echo "$target"
