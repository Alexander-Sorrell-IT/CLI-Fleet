#!/usr/bin/env bash
# Hook: TaskCompleted — quality gate before marking tasks done
# Exit code 2 = reject completion with feedback
# Exit code 0 = allow completion

set -uo pipefail

META_DIR="${META_TEAM_DIR:-$HOME/.cli-fleet/meta-teams}"
[[ ! -d "$META_DIR" && -d "$HOME/.claude/meta-teams" ]] && META_DIR="$HOME/.claude/meta-teams"
META_TEAM="${META_TEAM_NAME:-}"
TEAM="${TEAM_NAME:-}"

# Skip if not in multi-team context
[[ -z "$META_TEAM" || -z "$TEAM" ]] && exit 0

# Notify captain that a task was completed
DIR="$META_DIR/$META_TEAM"
[[ ! -d "$DIR" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/protocol.sh" 2>/dev/null || exit 0

# Post status update so captain sees task completion in real-time
meta_send "$META_TEAM" "$TEAM" "captain" "status" "Task completed by $TEAM" 2>/dev/null || true

# Allow completion
exit 0
