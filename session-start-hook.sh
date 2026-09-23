#!/bin/bash
# Session Start Hook for Gentle-AI
# Quiet daily model sync: runs once per day, full detail goes to
# results/session-start.log. Success prints nothing; failures go to stderr.
#
# On-demand full report + apply (after this file is sourced):
#   models-apply
#
# Add to your shell profile:
#   source /path/to/free-model-comparison/session-start-hook.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAILY_CHECK="$SCRIPT_DIR/daily-check.sh"
APPLY_CONFIG="$SCRIPT_DIR/apply-model-config.sh"
LAST_RUN_FILE="$SCRIPT_DIR/results/.last-daily-run"
LOCK_FILE="$SCRIPT_DIR/results/.last-daily-run.lock"
HOOK_LOG="$SCRIPT_DIR/results/session-start.log"

# Defined before the once-per-day guard so it is always available when sourced.
# Name reflects behavior: daily report + write opencode.jsonc (not status-only).
models-apply() {
    bash "$DAILY_CHECK" && bash "$APPLY_CONFIG"
}

# Only run once per day
today=$(date +%Y-%m-%d)

already_ran_today() {
    [ -f "$LAST_RUN_FILE" ] && [ "$(<"$LAST_RUN_FILE")" = "$today" ]
}

if already_ran_today; then
    return 0 2>/dev/null || exit 0
fi

mkdir -p "$SCRIPT_DIR/results"

# Serialize concurrent shells so only one runs the daily sync per stamp.
# flock is released automatically if a shell crashes mid-run, so there is
# no stale-lock recovery to manage.
exec 9>"$LOCK_FILE" || { return 0 2>/dev/null || exit 0; }
if ! flock -n 9; then
    # Another shell holds the lock (running right now, or just finished).
    exec 9>&-
    return 0 2>/dev/null || exit 0
fi
if already_ran_today; then
    # Re-check under the lock: the previous holder may have just stamped.
    exec 9>&-
    return 0 2>/dev/null || exit 0
fi

echo "===== $(date -Iseconds) session-start daily sync =====" >>"$HOOK_LOG" 2>&1

# Run daily check (fetches live models, updates registry).
# Only stamp last-run on success so a failed check retries next session.
if [ -f "$DAILY_CHECK" ]; then
    if bash "$DAILY_CHECK" >>"$HOOK_LOG" 2>&1; then
        echo "$today" > "$LAST_RUN_FILE"
    else
        echo "[Gentle-AI] Daily check FAILED — will retry on next session. Details: $HOOK_LOG" >&2
    fi
fi

# Apply model config to opencode.jsonc (reads tier + registry → patches agents)
if [ -f "$APPLY_CONFIG" ]; then
    if ! bash "$APPLY_CONFIG" >>"$HOOK_LOG" 2>&1; then
        echo "[Gentle-AI] Applying model config FAILED. Details: $HOOK_LOG" >&2
    fi
fi

exec 9>&-
