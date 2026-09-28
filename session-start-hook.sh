#!/bin/bash
# Session Start Hook for Gentle-AI
# Quiet model sync with a configurable frequency. One gate, two triggers:
#   bash session-start-hook.sh [opencode|shell]
#     shell    (default) — sourced from ~/.bashrc on every terminal start
#     opencode — fired by ~/.config/opencode/plugins/model-check.ts on every
#                OpenCode startup
# Frequency comes from .model-check-config (`check_frequency=<value>`):
#   session          = run on every opencode trigger; the shell trigger is inert
#   daily/weekly/monthly = either trigger at most once per 1 / 7 / 30 days,
#                        decided by the shared stamp results/.last-daily-run
#   Missing file/key/value → daily; unknown value → daily + one stderr notice.
# Success prints nothing; failures go to stderr; full detail goes to
# results/session-start.log.
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
FREQ_CONFIG="$SCRIPT_DIR/.model-check-config"

# Trigger: only an explicit first argument is honored; anything else (no
# argument, as when sourced from ~/.bashrc, or an unrecognized value) is the
# shell trigger, so the existing wiring keeps its behavior unchanged.
TRIGGER="${1:-}"
case "$TRIGGER" in
    opencode|shell) ;;
    *) TRIGGER="shell" ;;
esac

# Frequency: parse `check_frequency=<value>` from .model-check-config.
# Deliberately NOT sourced — the file may contain arbitrary text. Comments and
# blank lines are skipped; the last assignment wins.
CHECK_FREQUENCY=""
if [ -f "$FREQ_CONFIG" ]; then
    CHECK_FREQUENCY="$(sed -n 's/^[[:space:]]*check_frequency[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$FREQ_CONFIG" | tail -n 1)"
fi

case "$CHECK_FREQUENCY" in
    session|daily|weekly|monthly) ;;
    "") CHECK_FREQUENCY="daily" ;;   # Missing file/key/value → pre-existing behavior.
    *)
        echo "[Gentle-AI] unknown check_frequency \"$CHECK_FREQUENCY\" in .model-check-config — falling back to daily" >&2
        CHECK_FREQUENCY="daily"
        ;;
esac

# Defined before the gate so it is always available when sourced.
# Name reflects behavior: daily report + write opencode.jsonc (not status-only).
models-apply() {
    bash "$DAILY_CHECK" && bash "$APPLY_CONFIG"
}

# ─── Frequency gate ──────────────────────────────────────────────────────────
# Mode table (check_frequency × trigger):
#   session  | shell:    return immediately, run NOTHING (no mkdir/lock/network)
#            | opencode: run unconditionally (every OpenCode startup)
#   daily    | both triggers: run only when the shared stamp
#   weekly   | results/.last-daily-run is absent or older than 1 / 7 / 30 days
#   monthly  | (flock still serializes concurrent runs; the stamp is written
#            |  only on a successful daily-check.sh run)
#   unknown  | falls back to daily + one stderr notice; always exits 0
case "$CHECK_FREQUENCY" in
    weekly) MAX_AGE_DAYS=7 ;;
    monthly) MAX_AGE_DAYS=30 ;;
    *) MAX_AGE_DAYS=1 ;;   # daily (and the unknown-value fallback)
esac

# Stale = stamp absent or last written more than $1 days ago (mtime-based, so
# shell and opencode triggers always share one stamp).
stamp_is_stale() {
    [ -f "$LAST_RUN_FILE" ] || return 0
    [ -z "$(find "$LAST_RUN_FILE" -mtime "-$1" 2>/dev/null)" ]
}

if [ "$CHECK_FREQUENCY" = "session" ]; then
    if [ "$TRIGGER" = "shell" ]; then
        # session mode: plain terminal starts must not touch anything.
        return 0 2>/dev/null || exit 0
    fi
    # session mode + opencode trigger: run unconditionally.
elif ! stamp_is_stale "$MAX_AGE_DAYS"; then
    return 0 2>/dev/null || exit 0
fi

mkdir -p "$SCRIPT_DIR/results"

# Serialize concurrent runs so only one refreshes per stamp.
# flock is released automatically if a shell crashes mid-run, so there is
# no stale-lock recovery to manage.
exec 9>"$LOCK_FILE" || { return 0 2>/dev/null || exit 0; }
if ! flock -n 9; then
    # Another run holds the lock (running right now, or just finished).
    exec 9>&-
    return 0 2>/dev/null || exit 0
fi
if [ "$CHECK_FREQUENCY" != "session" ] && ! stamp_is_stale "$MAX_AGE_DAYS"; then
    # Re-check under the lock: the previous holder may have just stamped.
    # session mode skips this — every opencode invocation must run.
    exec 9>&-
    return 0 2>/dev/null || exit 0
fi

today=$(date +%Y-%m-%d)

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
