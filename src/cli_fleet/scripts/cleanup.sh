#!/usr/bin/env bash
# cleanup.sh — Tear down a multi-team operation
# Usage: ./cleanup.sh <meta-team-name> [--force]
#
# Without --force: only cleans up if all processes are stopped
# With --force: kills all processes then cleans up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
META_DIR="${META_TEAM_DIR:-$HOME/.claude/meta-teams}"

META_TEAM="${1:?Usage: $0 <meta-team-name> [--force]}"
FORCE="${2:-}"
DIR="$META_DIR/$META_TEAM"

if [[ ! -d "$DIR" ]]; then
    echo "Error: meta-team '$META_TEAM' not found at $DIR"
    exit 1
fi

# Check for running processes
RUNNING=0
if [[ -f "$DIR/pids.txt" ]]; then
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            ((RUNNING++))
            if [[ "$FORCE" == "--force" ]]; then
                echo "Killing PID $pid..."
                kill "$pid" 2>/dev/null || true
            fi
        fi
    done < "$DIR/pids.txt"
fi

if [[ $RUNNING -gt 0 && "$FORCE" != "--force" ]]; then
    echo "Error: $RUNNING team processes still running."
    echo "Use --force to kill them, or stop them manually first."
    echo ""
    echo "Running PIDs:"
    while read -r pid; do
        kill -0 "$pid" 2>/dev/null && echo "  $pid (running)"
    done < "$DIR/pids.txt"
    exit 1
fi

# Wait a moment for force-killed processes
[[ "$FORCE" == "--force" ]] && sleep 2

# Archive findings before cleanup
FINDINGS_COUNT=$(ls "$DIR/findings/"*.json 2>/dev/null | wc -l)
if [[ $FINDINGS_COUNT -gt 0 ]]; then
    ARCHIVE="$DIR/../${META_TEAM}-findings-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$ARCHIVE" -C "$DIR" findings/ 2>/dev/null || true
    echo "Archived $FINDINGS_COUNT findings to: $ARCHIVE"
fi

# Archive logs
LOG_COUNT=$(ls "$DIR/logs/"*.log 2>/dev/null | wc -l)
if [[ $LOG_COUNT -gt 0 ]]; then
    ARCHIVE="$DIR/../${META_TEAM}-logs-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$ARCHIVE" -C "$DIR" logs/ 2>/dev/null || true
    echo "Archived $LOG_COUNT logs to: $ARCHIVE"
fi

# Remove shared state
echo "Removing shared state: $DIR"
rm -rf "$DIR"

echo ""
echo "Meta-team '$META_TEAM' cleaned up."
echo "Findings and logs archived in: $META_DIR/"
