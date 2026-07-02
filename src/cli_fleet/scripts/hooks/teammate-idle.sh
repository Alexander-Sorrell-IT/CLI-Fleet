#!/usr/bin/env bash
# Hook: TeammateIdle — prevents teammates from quitting early
# Exit code 2 = send feedback and keep teammate working
# Exit code 0 = allow idle (teammate is done)
#
# Checks: did the teammate post findings? Did they run enough tools?
# If not, exit 2 to push them back to work.

set -uo pipefail

META_DIR="${META_TEAM_DIR:-$HOME/.cli-fleet/meta-teams}"
[[ ! -d "$META_DIR" && -d "$HOME/.claude/meta-teams" ]] && META_DIR="$HOME/.claude/meta-teams"
META_TEAM="${META_TEAM_NAME:-}"
TEAM="${TEAM_NAME:-}"

# Skip if not in multi-team context
[[ -z "$META_TEAM" || -z "$TEAM" ]] && exit 0

DIR="$META_DIR/$META_TEAM"
[[ ! -d "$DIR" ]] && exit 0

# Check if this team has posted any findings
FINDING_COUNT=$(ls "$DIR/findings/${TEAM}-"*.json 2>/dev/null | wc -l)

# Check unread messages (teammate might have new directives)
CURSOR_FILE="$DIR/status/${TEAM}.cursor"
LAST_READ="0"
[[ -f "$CURSOR_FILE" ]] && LAST_READ=$(cat "$CURSOR_FILE")

UNREAD=0
for msg_file in "$DIR/mailbox/"*.json; do
    [[ ! -f "$msg_file" ]] && continue
    basename=$(basename "$msg_file")
    msg_ts="${basename%%-*}"
    (( msg_ts <= LAST_READ )) && continue
    to=$(python3 -c "import json; print(json.load(open('$msg_file'))['to'])" 2>/dev/null || echo "")
    if [[ "$to" == "$TEAM" || "$to" == "all" ]]; then
        ((UNREAD++))
    fi
done

# If there are unread messages, keep working
if [[ $UNREAD -gt 0 ]]; then
    echo "You have $UNREAD unread cross-team messages. Check your mailbox before going idle."
    echo "Run: source $(dirname "$0")/../lib/protocol.sh && meta_read_messages \"$META_TEAM\" \"$TEAM\""
    exit 2
fi

# Allow idle — teammate has handled everything
exit 0
