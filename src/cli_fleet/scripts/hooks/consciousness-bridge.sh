#!/usr/bin/env bash
# Hook: consciousness-bridge.sh
# Type: UserPromptSubmit — bridges consciousness file signals to FleetCode mailbox
# AND bridges FleetCode mailbox messages into the consciousness stream
#
# Two-way bridge:
#   consciousness → mailbox (when neurons find critical stuff)
#   mailbox → consciousness (when other brains send intel)

set -uo pipefail

META_DIR="${META_TEAM_DIR:-$HOME/.claude/meta-teams}"
META_TEAM="${META_TEAM_NAME:-}"
TEAM="${TEAM_NAME:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

[[ -z "$META_TEAM" || -z "$TEAM" ]] && exit 0

DIR="$META_DIR/$META_TEAM"
[[ ! -d "$DIR" ]] && exit 0

# Find this team's consciousness file
CONSCIOUSNESS="$DIR/workdirs/$TEAM/consciousness.md"
[[ ! -f "$CONSCIOUSNESS" ]] && CONSCIOUSNESS="/tmp/brain-stream/$TEAM/consciousness.md"
[[ ! -f "$CONSCIOUSNESS" ]] && exit 0

# === INBOUND: FleetCode mailbox → consciousness stream ===
# Read unread cross-team messages and inject them as stimuli
CURSOR_FILE="$DIR/status/${TEAM}-brain.cursor"
LAST_READ="0"
[[ -f "$CURSOR_FILE" ]] && LAST_READ=$(cat "$CURSOR_FILE")

LATEST_TS="$LAST_READ"
for msg_file in "$DIR/mailbox/"*.json; do
    [[ ! -f "$msg_file" ]] && continue
    basename=$(basename "$msg_file")
    msg_ts="${basename%%-*}"
    (( msg_ts <= LAST_READ )) && continue

    to=$(python3 -c "import json; print(json.load(open('$msg_file'))['to'])" 2>/dev/null || echo "")
    if [[ "$to" == "$TEAM" || "$to" == "all" ]]; then
        from=$(python3 -c "import json; print(json.load(open('$msg_file'))['from'])" 2>/dev/null || echo "unknown")
        content=$(python3 -c "import json; print(json.load(open('$msg_file'))['content'])" 2>/dev/null || echo "")
        msg_type=$(python3 -c "import json; print(json.load(open('$msg_file'))['type'])" 2>/dev/null || echo "message")

        # Skip our own messages
        [[ "$from" == "$TEAM" ]] && continue

        # Inject into consciousness stream
        echo "[$(date +%H:%M:%S)] CROSS-BRAIN($from): $content" >> "$CONSCIOUSNESS"

        (( msg_ts > LATEST_TS )) && LATEST_TS="$msg_ts"
    fi
done

if (( LATEST_TS > LAST_READ )); then
    mkdir -p "$DIR/status"
    echo "$LATEST_TS" > "$CURSOR_FILE"
fi

# === OUTBOUND: Also run the standard mailbox check ===
# (The regular check-mailbox.sh handles injecting into Claude's context)

exit 0
