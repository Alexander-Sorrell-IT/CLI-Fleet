#!/usr/bin/env bash
# status.sh — Show status of all teams, tasks, findings, and mailbox
# Usage: ./status.sh <meta-team-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/protocol.sh"

META_TEAM="${1:?Usage: $0 <meta-team-name>}"
DIR="$META_DIR/$META_TEAM"

if [[ ! -d "$DIR" ]]; then
    echo "Error: meta-team '$META_TEAM' not found at $DIR"
    exit 1
fi

meta_status "$META_TEAM"

# Show log tail for each team
echo "--- Recent Log Output ---"
for logfile in "$DIR/logs/"*.log; do
    [[ ! -f "$logfile" ]] && continue
    team=$(basename "$logfile" .log)
    lines=$(wc -l < "$logfile")
    echo "  $team: $lines lines (tail -f $logfile)"
done
echo ""

# Show process health
echo "--- Process Health ---"
if [[ -f "$DIR/pids.txt" ]]; then
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "  PID $pid: running"
        else
            echo "  PID $pid: stopped"
        fi
    done < "$DIR/pids.txt"
else
    echo "  (no pids.txt found)"
fi
