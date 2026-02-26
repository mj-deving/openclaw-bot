#!/bin/bash
# OpenClaw VPS backup script
# Backs up config and memory database to ~/.openclaw/backups/
# Deployed to: ~/scripts/backup.sh on VPS
# Cron: 0 3 * * * (daily at 3 AM)

set -euo pipefail

BACKUP_DIR="$HOME/.openclaw/backups"
DATE=$(date +%Y%m%d-%H%M%S)
LOG="$HOME/.openclaw/logs/backup.log"

log() { echo "$(date -Iseconds): $1" >> "$LOG"; }

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Back up config (contains secrets — keep permissions tight)
if [ -f "$HOME/.openclaw/openclaw.json" ]; then
    cp "$HOME/.openclaw/openclaw.json" "$BACKUP_DIR/config-$DATE.json"
    chmod 600 "$BACKUP_DIR/config-$DATE.json"
    log "Backed up config → config-$DATE.json"
else
    log "WARNING: openclaw.json not found, skipping config backup"
fi

# Back up memory database (sqlite with vector embeddings)
if [ -f "$HOME/.openclaw/memory/main.sqlite" ]; then
    cp "$HOME/.openclaw/memory/main.sqlite" "$BACKUP_DIR/memory-$DATE.sqlite"
    chmod 600 "$BACKUP_DIR/memory-$DATE.sqlite"
    log "Backed up memory → memory-$DATE.sqlite"
else
    log "WARNING: memory/main.sqlite not found, skipping memory backup"
fi

# Back up memory markdown files (source material for embeddings)
if [ -d "$HOME/.openclaw/workspace/memory" ]; then
    tar czf "$BACKUP_DIR/memory-files-$DATE.tar.gz" -C "$HOME/.openclaw/workspace" memory/
    chmod 600 "$BACKUP_DIR/memory-files-$DATE.tar.gz"
    log "Backed up memory files → memory-files-$DATE.tar.gz"
fi

# Prune backups older than 30 days
PRUNED=$(find "$BACKUP_DIR" -type f -mtime +30 -delete -print | wc -l)
if [ "$PRUNED" -gt 0 ]; then
    log "Pruned $PRUNED backup files older than 30 days"
fi

# Prune daily reports older than 90 days
REPORTS_DIR="$HOME/.openclaw/reports"
if [ -d "$REPORTS_DIR" ]; then
    PRUNED_REPORTS=$(find "$REPORTS_DIR" -name "*.md" -mtime +90 -delete -print | wc -l)
    if [ "$PRUNED_REPORTS" -gt 0 ]; then
        log "Pruned $PRUNED_REPORTS report files older than 90 days"
    fi
fi

log "Backup complete"
