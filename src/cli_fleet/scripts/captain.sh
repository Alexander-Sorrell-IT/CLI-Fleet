#!/usr/bin/env bash
# captain.sh — Functions for the captain session (the one the user talks to)
# Source this in the main claude session to get captain commands.
#
# Usage: source multi-team/captain.sh <meta-team-name>
#
# Then use these functions:
#   fleet_status          — full dashboard
#   fleet_findings        — list all findings with details
#   fleet_send <to> <msg> — send directive to a team or "all"
#   fleet_ask <to> <msg>  — ask a team a question
#   fleet_focus <to> <msg>— redirect a team's focus
#   fleet_mailbox         — read all unread messages for captain
#   fleet_logs [team]     — tail recent log output
#   fleet_escalate <msg>  — broadcast URGENT to all teams
#   fleet_reassign <task-id> <team> — reassign a cross-team task
#   fleet_kill <team>     — shut down a specific team
#   fleet_cleanup         — tear down everything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/protocol.sh"

CAPTAIN_META="${1:?Usage: source captain.sh <meta-team-name>}"
CAPTAIN_DIR="$META_DIR/$CAPTAIN_META"

if [[ ! -d "$CAPTAIN_DIR" ]]; then
    echo "Error: meta-team '$CAPTAIN_META' not found. Launch teams first with launch.sh"
    return 1 2>/dev/null || exit 1
fi

# Register captain in the registry
meta_register_team "$CAPTAIN_META" "captain" "Coordinator — reads status, sends directives, steers all teams" $$ "$(pwd)"

echo "Captain registered for meta-team: $CAPTAIN_META"
echo ""
echo "Commands:"
echo "  fleet_status          — full dashboard"
echo "  fleet_findings        — all findings with details"
echo "  fleet_send <to> <msg> — directive to team or 'all'"
echo "  fleet_ask <to> <msg>  — question to a team"
echo "  fleet_focus <to> <msg>— redirect a team's focus"
echo "  fleet_mailbox         — read unread messages"
echo "  fleet_logs [team]     — recent log output"
echo "  fleet_escalate <msg>  — URGENT broadcast to all"
echo "  fleet_kill <team>     — shut down a team"
echo "  fleet_cleanup         — tear down everything"

fleet_status() {
    meta_status "$CAPTAIN_META"
}

fleet_findings() {
    echo "=== All Findings ==="
    for f in "$CAPTAIN_DIR/findings/"*.json; do
        [[ ! -f "$f" ]] && { echo "(none)"; return; }
        python3 -c "
import json
with open('$f') as fh:
    d = json.load(fh)
print(f\"[{d['severity']:8s}] {d['team']:15s} | {d['title']}\")
print(f\"           {d['details']}\")
print(f\"           {d['timestamp']}\")
print()
"
    done
}

fleet_send() {
    local to="${1:?Usage: fleet_send <team|all> <message>}"
    shift
    local msg="$*"
    meta_send "$CAPTAIN_META" "captain" "$to" "directive" "$msg"
    echo "Sent directive to $to"
}

fleet_ask() {
    local to="${1:?Usage: fleet_ask <team> <question>}"
    shift
    local msg="$*"
    meta_send "$CAPTAIN_META" "captain" "$to" "question" "$msg"
    echo "Asked $to: $msg"
}

fleet_focus() {
    local to="${1:?Usage: fleet_focus <team> <new focus>}"
    shift
    local msg="$*"
    meta_send "$CAPTAIN_META" "captain" "$to" "directive" "REDIRECT: Drop current task. New priority: $msg"
    echo "Redirected $to to: $msg"
}

fleet_mailbox() {
    echo "=== Unread Messages for Captain ==="
    meta_read_messages "$CAPTAIN_META" "captain"
    echo "(end)"
}

fleet_logs() {
    local team="${1:-}"
    if [[ -n "$team" ]]; then
        local logfile="$CAPTAIN_DIR/logs/${team}.log"
        if [[ -f "$logfile" ]]; then
            echo "=== Last 30 lines: $team ==="
            tail -30 "$logfile"
        else
            echo "No log for $team"
        fi
    else
        for logfile in "$CAPTAIN_DIR/logs/"*.log; do
            [[ ! -f "$logfile" ]] && continue
            local t
            t=$(basename "$logfile" .log)
            echo "=== $t ($(wc -l < "$logfile") lines) ==="
            tail -5 "$logfile"
            echo ""
        done
    fi
}

fleet_escalate() {
    local msg="${1:?Usage: fleet_escalate <urgent message>}"
    meta_send "$CAPTAIN_META" "captain" "all" "directive" "URGENT: $msg"
    echo "URGENT broadcast sent to all teams"
}

fleet_reassign() {
    local task_id="${1:?Usage: fleet_reassign <task-id> <team>}"
    local team="${2:?Missing team name}"
    meta_update_task "$CAPTAIN_META" "$task_id" "pending" ""
    meta_add_task "$CAPTAIN_META" "$task_id" "Reassigned to $team" "$team" ""
    meta_send "$CAPTAIN_META" "captain" "$team" "task" "You have been assigned task: $task_id"
    echo "Reassigned $task_id to $team"
}

fleet_kill() {
    local team="${1:?Usage: fleet_kill <team-name>}"
    # Find PID from registry
    local pid
    pid=$(python3 -c "
import json
with open('$CAPTAIN_DIR/registry.json') as f:
    reg = json.load(f)
for t in reg['teams']:
    if t['name'] == '$team':
        print(t['pid'])
        break
" 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        echo "Killed $team (PID $pid)"
    else
        echo "$team is not running (PID: ${pid:-unknown})"
    fi
}

fleet_cleanup() {
    bash "$SCRIPT_DIR/cleanup.sh" "$CAPTAIN_META" --force
}
