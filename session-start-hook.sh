#!/bin/bash
# Session Start Hook for Gentle-AI
# Quiet daily model sync: runs once per day, full detail goes to
# results/session-start.log. Success prints nothing; failures go to stderr.
#
# On-demand full report (after this file is sourced):
#   models-status
#
# Add to your shell profile:
#   source /home/francesc/projects/free-model-comparison/session-start-hook.sh

SCRIPT_DIR="/home/francesc/projects/free-model-comparison"
DAILY_CHECK="$SCRIPT_DIR/daily-check.sh"
APPLY_CONFIG="$SCRIPT_DIR/apply-model-config.sh"
LAST_RUN_FILE="$SCRIPT_DIR/results/.last-daily-run"
HOOK_LOG="$SCRIPT_DIR/results/session-start.log"

# Defined before the once-per-day guard so it is always available when sourced.
models-status() {
    bash "$SCRIPT_DIR/daily-check.sh" && bash "$SCRIPT_DIR/apply-model-config.sh"
}

# Only run once per day
today=$(date +%Y-%m-%d)
if [ -f "$LAST_RUN_FILE" ]; then
    last_run=$(cat "$LAST_RUN_FILE")
    if [ "$last_run" = "$today" ]; then
        # Already ran today, skip
        return 0 2>/dev/null || exit 0
    fi
fi

mkdir -p "$SCRIPT_DIR/results"
{
    echo "===== $(date -Iseconds) session-start daily sync ====="
} >>"$HOOK_LOG" 2>&1

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
