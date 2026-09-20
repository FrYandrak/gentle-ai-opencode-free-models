#!/bin/bash
# Session Start Hook for Gentle-AI
# Runs daily model check + applies model config to opencode.jsonc
# Sources this at the beginning of each session to ensure
# fresh model assignments.
#
# Add to your shell profile:
#   source /home/francesc/projects/free-model-comparison/session-start-hook.sh

SCRIPT_DIR="/home/francesc/projects/free-model-comparison"
DAILY_CHECK="$SCRIPT_DIR/daily-check.sh"
APPLY_CONFIG="$SCRIPT_DIR/apply-model-config.sh"
CONFIG_FILE="$SCRIPT_DIR/.privacy-config"
LAST_RUN_FILE="$SCRIPT_DIR/results/.last-daily-run"
LAST_MODELS_FILE="$SCRIPT_DIR/results/.last-models-hash"

# Only run once per day
today=$(date +%Y-%m-%d)
if [ -f "$LAST_RUN_FILE" ]; then
    last_run=$(cat "$LAST_RUN_FILE")
    if [ "$last_run" = "$today" ]; then
        # Already ran today, skip
        return 0 2>/dev/null || exit 0
    fi
fi

echo "[Gentle-AI] First session of the day — checking models..."

# Run daily check (fetches live models, updates registry)
if [ -f "$DAILY_CHECK" ]; then
    bash "$DAILY_CHECK"
    echo "$today" > "$LAST_RUN_FILE"
    echo ""
fi

# Apply model config to opencode.jsonc (reads tier + registry → patches agents)
if [ -f "$APPLY_CONFIG" ]; then
    echo "[Gentle-AI] Applying model config to opencode.jsonc..."
    bash "$APPLY_CONFIG"
    echo ""
fi

echo "[Gentle-AI] Ready. Models configured for today."
