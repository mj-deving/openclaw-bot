# Database Maintenance

SQLite maintenance reference for OpenClaw. Based on real-world findings from Clelp's compaction loop incident ([source](https://clelp.ai/blog/fixing-openclaw-compaction-loop)) and our own Gregor audit.

## The Compaction Loop Problem

OpenClaw can enter a destructive compaction loop where the agent spends all its time compacting context instead of responding. Warning signs:

- "Compacting context..." appearing every few seconds
- `/reset` command proving ineffective
- Multi-minute response times
- `main.sqlite` exceeding 300MB
- Large pile-up of `.jsonl` files in sessions directory

## Root Causes

### 1. Embedding Cache Bloat
The `embedding_cache` table has no expiration logic. Every embedding ever generated persists indefinitely. Clelp's hit 184MB.

### 2. Aggressive Context Pruning
Low TTL + low `keepLastAssistants` creates a feedback loop: rapid pruning triggers constant compaction, which triggers more pruning. Clelp had TTL=30min and `keepLastAssistants=3`.

**Recommended config:**
- `context.pruning.ttl` = 2 hours (minimum)
- `context.pruning.keepLastAssistants` = 8

### 3. Orphaned Session Files
`.jsonl` transcript files in the sessions directory can accumulate without corresponding active sessions, consuming index overhead during context lookups.

### 4. SQLite Journal Mode
Default DELETE mode creates performance bottlenecks under frequent access. WAL (Write-Ahead Logging) is better for concurrent/frequent-access workloads:

```sql
PRAGMA journal_mode=WAL;
```

## Critical Gotcha: Millisecond Timestamps

OpenClaw stores `updated_at` as **millisecond** epoch timestamps. Standard SQLite `unixepoch()` returns **seconds**. DELETE queries silently match zero rows unless you multiply by 1000:

```sql
-- WRONG: matches nothing
DELETE FROM chunks WHERE updated_at < (unixepoch() - 1209600);

-- CORRECT: multiply by 1000
DELETE FROM chunks WHERE source='sessions' AND updated_at < ((unixepoch()-1209600)*1000);
```

This is the single most dangerous gotcha — cleanup scripts appear to work but silently do nothing.

## Remediation Steps

**Preparation:**
1. Hot-backup: `sqlite3 main.sqlite ".backup backup.sqlite"` (not `cp`)
2. Enable WAL: `PRAGMA journal_mode=WAL`
3. Confirm no active writes before cleanup

**Cleanup (requires backup first):**
4. Remove session chunks older than 14 days:
   ```sql
   DELETE FROM chunks WHERE source='sessions' AND updated_at < ((unixepoch()-1209600)*1000);
   ```
5. Trim embedding cache (30-day window):
   ```sql
   DELETE FROM embedding_cache WHERE updated_at < ((unixepoch()-2592000)*1000);
   ```
6. VACUUM (requires 1x database size in free disk space):
   ```sql
   VACUUM;
   ```
7. Integrity check:
   ```sql
   PRAGMA integrity_check;
   ```

**Prevention:**
8. Adjust pruning config (TTL >= 2h, keepLastAssistants >= 8)
9. Weekly automated maintenance via cron

## Size Thresholds

| Size | Status | Action |
|------|--------|--------|
| < 250MB | Green | Normal |
| 250-300MB | Warning | Schedule cleanup |
| > 300MB | Critical | Immediate maintenance |

## Storage Inefficiency Note

Embeddings are stored as JSON text arrays (~19KB each) rather than binary BLOBs (~6KB) — a 3x size multiplier. This is an upstream OpenClaw issue and can't be fixed locally.

## Health Check Queries

```sql
-- Database size (run from shell)
-- ls -lh ~/.openclaw/main.sqlite

-- Journal mode
PRAGMA journal_mode;

-- Table sizes
SELECT name, SUM(pgsize) as size_bytes FROM dbstat GROUP BY name ORDER BY size_bytes DESC;

-- Embedding cache row count and age range
SELECT COUNT(*) as rows,
       datetime(MIN(updated_at)/1000, 'unixepoch') as oldest,
       datetime(MAX(updated_at)/1000, 'unixepoch') as newest
FROM embedding_cache;

-- Session chunk count
SELECT COUNT(*) FROM chunks WHERE source='sessions';

-- Orphaned session files (run from shell)
-- find ~/.openclaw/sessions/ -name '*.jsonl' | wc -l
```

## Gregor Baseline (2026-03-02)

**Database:** `~/.openclaw/memory/main.sqlite` (not `~/.openclaw/main.sqlite`)

| Metric | Value | Status |
|--------|-------|--------|
| Database size | 8.2 MB | Green (well under 250MB) |
| Journal mode | `wal` | Applied 2026-03-02 |
| Embedding cache | 198 rows, 3.08 MB | Healthy (oldest: Feb 20, newest: Mar 2) |
| Session chunks | 84 | Low |
| Orphaned `.jsonl` files | 0 | Clean |
| Context pruning TTL | 7200s (2 hours) | Applied 2026-03-02 |
| Context pruning keepLastAssistants | 8 | Applied 2026-03-02 |

**Top tables by size:**
- `embedding_cache`: 3.2 MB (40% of DB)
- `chunks_vec_vector_chunks00`: 3.0 MB (37%)
- `chunks`: 1.6 MB (20%)

**Assessment:** Gregor is healthy. Both preventive fixes applied on 2026-03-02:

1. ~~Switch to WAL mode~~ — **Done.** `PRAGMA journal_mode=WAL` applied via Python sqlite3.
2. ~~Set explicit pruning config~~ — **Done.** TTL=7200s (2h), keepLastAssistants=8 written to `openclaw.json`.

**Note:** `sqlite3` CLI is not installed on the VPS. Use Python's `sqlite3` module for all queries. Also no `dbstat` extension issues — it works via Python.
