#!/usr/bin/env bash
# Hook: stream-stall-check.sh
# Type: TeammateIdle — detects stalled brain streams
# Exit code 2 = keep teammate working (stream stalled, needs stimulus)
# Exit code 0 = allow idle

set -uo pipefail

CF="${CONSCIOUSNESS_FILE:-}"
[[ -z "$CF" || ! -f "$CF" ]] && exit 0

LAST_LINE=$(tail -1 "$CF" 2>/dev/null)
[[ -z "$LAST_LINE" ]] && exit 0

LAST_TIME=$(echo "$LAST_LINE" | grep -oP '\[\K[0-9:]+' 2>/dev/null || echo "")
[[ -z "$LAST_TIME" ]] && exit 0

NOW=$(date +%s)
LAST_EPOCH=$(date -d "$LAST_TIME" +%s 2>/dev/null || echo 0)
DIFF=$((NOW - LAST_EPOCH))

if [[ $DIFF -gt 120 ]]; then
    echo "Stream stalled for ${DIFF}s. Read $CF and inject a specific stimulus about an unexplored angle." >&2
    exit 2
fi

exit 0
