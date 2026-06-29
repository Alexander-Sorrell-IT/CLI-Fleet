#!/usr/bin/env bash
# send.sh — Send a cross-team message
# Usage: ./send.sh <meta-team> <from> <to|all> <type> "<content>"
# Types: finding, task, question, status, directive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/protocol.sh"

META_TEAM="${1:?Usage: $0 <meta-team> <from> <to|all> <type> \"<content>\"}"
FROM="${2:?Missing: from team name}"
TO="${3:?Missing: to team name (or 'all')}"
TYPE="${4:?Missing: message type (finding|task|question|status|directive)}"
CONTENT="${5:?Missing: message content}"

DIR="$META_DIR/$META_TEAM"
if [[ ! -d "$DIR" ]]; then
    echo "Error: meta-team '$META_TEAM' not found"
    exit 1
fi

MSG_FILE=$(meta_send "$META_TEAM" "$FROM" "$TO" "$TYPE" "$CONTENT")
echo "Sent: $MSG_FILE"
