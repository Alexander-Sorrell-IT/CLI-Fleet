#!/usr/bin/env bash
# Hook: check-mailbox.sh
# Type: UserPromptSubmit — injects cross-team messages as additional context
# Install: add to settings.json hooks.UserPromptSubmit
#
# Env vars expected:
#   META_TEAM_NAME  — name of the meta-team (e.g., "hunt-lz")
#   TEAM_NAME       — this team's name (e.g., "team-evm-v1")

set -euo pipefail

META_DIR="${META_TEAM_DIR:-$HOME/.cli-fleet/meta-teams}"
[[ ! -d "$META_DIR" && -d "$HOME/.claude/meta-teams" ]] && META_DIR="$HOME/.claude/meta-teams"
META_TEAM="${META_TEAM_NAME:-}"
TEAM="${TEAM_NAME:-}"

# Skip if not in a multi-team context
[[ -z "$META_TEAM" || -z "$TEAM" ]] && exit 0

DIR="$META_DIR/$META_TEAM"
[[ ! -d "$DIR/mailbox" ]] && exit 0

CURSOR_FILE="$DIR/status/${TEAM}.cursor"
LAST_READ="0"
[[ -f "$CURSOR_FILE" ]] && LAST_READ=$(cat "$CURSOR_FILE")

NEW_MESSAGES=""
LATEST_TS="$LAST_READ"

for msg_file in "$DIR/mailbox/"*.json; do
    [[ ! -f "$msg_file" ]] && continue

    basename=$(basename "$msg_file")
    msg_ts="${basename%%-*}"

    # Skip already-read
    (( msg_ts <= LAST_READ )) && continue

    # Check if message is for us or broadcast
    to=$(python3 -c "import json; print(json.load(open('$msg_file'))['to'])" 2>/dev/null || echo "")
    if [[ "$to" == "$TEAM" || "$to" == "all" ]]; then
        from=$(python3 -c "import json; print(json.load(open('$msg_file'))['from'])" 2>/dev/null || echo "unknown")
        msg_type=$(python3 -c "import json; print(json.load(open('$msg_file'))['type'])" 2>/dev/null || echo "message")
        content=$(python3 -c "import json; print(json.load(open('$msg_file'))['content'])" 2>/dev/null || echo "")

        NEW_MESSAGES+="[CROSS-TEAM ${msg_type^^}] From ${from}: ${content}"$'\n'

        (( msg_ts > LATEST_TS )) && LATEST_TS="$msg_ts"
    fi
done

# Update cursor
if (( LATEST_TS > LAST_READ )); then
    mkdir -p "$DIR/status"
    echo "$LATEST_TS" > "$CURSOR_FILE"
fi

# Output new messages as hook context (shows up in Claude's context)
if [[ -n "$NEW_MESSAGES" ]]; then
    echo "## Cross-Team Mailbox (${META_TEAM})"
    echo ""
    echo "$NEW_MESSAGES"
    echo ""
    echo "Reply to any team with: source multi-team/lib/protocol.sh && meta_send \"$META_TEAM\" \"$TEAM\" \"<target>\" \"<type>\" \"<content>\""
fi
