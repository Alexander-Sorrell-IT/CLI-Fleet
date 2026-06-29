#!/usr/bin/env bash
# Multi-team communication protocol — shared functions
# All teams use the same message format and directory layout.

META_DIR="${META_TEAM_DIR:-$HOME/.claude/meta-teams}"

# Initialize a meta-team's shared state directory
meta_init() {
    local meta_name="$1"
    local dir="$META_DIR/$meta_name"
    mkdir -p "$dir"/{mailbox,findings,tasks,status}

    # Registry: tracks all teams
    if [[ ! -f "$dir/registry.json" ]]; then
        echo '{"meta_team":"'"$meta_name"'","created":"'"$(date -Iseconds)"'","teams":[]}' | python3 -m json.tool > "$dir/registry.json"
    fi

    # Cross-team task list
    if [[ ! -f "$dir/tasks.json" ]]; then
        echo '{"tasks":[]}' > "$dir/tasks.json"
    fi

    echo "$dir"
}

# Register a team in the registry
meta_register_team() {
    local meta_name="$1"
    local team_name="$2"
    local role="$3"
    local pid="$4"
    local workdir="$5"
    local dir="$META_DIR/$meta_name"

    python3 -c "
import json, sys
with open('$dir/registry.json') as f:
    reg = json.load(f)
reg['teams'] = [t for t in reg['teams'] if t['name'] != '$team_name']
reg['teams'].append({
    'name': '$team_name',
    'role': '$role',
    'pid': $pid,
    'workdir': '$workdir',
    'status': 'active',
    'registered': '$(date -Iseconds)'
})
with open('$dir/registry.json', 'w') as f:
    json.dump(reg, f, indent=2)
"
}

# Send a message (file-based mailbox)
meta_send() {
    local meta_name="$1"
    local from="$2"
    local to="$3"       # team name or "all"
    local msg_type="$4"  # finding|task|question|status|directive
    local content="$5"
    local dir="$META_DIR/$meta_name"
    local ts
    ts=$(date +%s%N)
    local msg_file="$dir/mailbox/${ts}-${from}-to-${to}.json"

    python3 -c "
import json
msg = {
    'id': '${ts}',
    'from': '$from',
    'to': '$to',
    'type': '$msg_type',
    'timestamp': '$(date -Iseconds)',
    'content': $(python3 -c "import json; print(json.dumps('''$content'''))")
}
with open('$msg_file', 'w') as f:
    json.dump(msg, f, indent=2)
"
    echo "$msg_file"
}

# Read unread messages for a team
meta_read_messages() {
    local meta_name="$1"
    local team_name="$2"
    local dir="$META_DIR/$meta_name"
    local cursor_file="$dir/status/${team_name}.cursor"
    local last_read="0"

    [[ -f "$cursor_file" ]] && last_read=$(cat "$cursor_file")

    local new_msgs=()
    for msg_file in "$dir/mailbox/"*.json; do
        [[ ! -f "$msg_file" ]] && continue
        local basename
        basename=$(basename "$msg_file")
        local msg_ts="${basename%%-*}"

        # Skip already-read messages
        (( msg_ts <= last_read )) && continue

        # Check if message is for us or broadcast
        local to
        to=$(python3 -c "import json; print(json.load(open('$msg_file'))['to'])")
        if [[ "$to" == "$team_name" || "$to" == "all" ]]; then
            cat "$msg_file"
            echo "---"
            new_msgs+=("$msg_ts")
        fi
    done

    # Update cursor to latest read
    if [[ ${#new_msgs[@]} -gt 0 ]]; then
        printf '%s\n' "${new_msgs[@]}" | sort -n | tail -1 > "$cursor_file"
    fi
}

# Post a finding to shared findings directory
meta_post_finding() {
    local meta_name="$1"
    local team_name="$2"
    local finding_id="$3"
    local severity="$4"
    local title="$5"
    local details="$6"
    local dir="$META_DIR/$meta_name"
    local finding_file="$dir/findings/${team_name}-${finding_id}.json"

    python3 -c "
import json
finding = {
    'id': '$finding_id',
    'team': '$team_name',
    'severity': '$severity',
    'title': $(python3 -c "import json; print(json.dumps('''$title'''))"),
    'details': $(python3 -c "import json; print(json.dumps('''$details'''))"),
    'timestamp': '$(date -Iseconds)',
    'status': 'new'
}
with open('$finding_file', 'w') as f:
    json.dump(finding, f, indent=2)
"

    # Broadcast finding to all teams
    meta_send "$meta_name" "$team_name" "all" "finding" "New finding: [$severity] $title — see $finding_file"
}

# Add/update a cross-team task
meta_add_task() {
    local meta_name="$1"
    local task_id="$2"
    local title="$3"
    local assigned_to="$4"  # team name or empty
    local depends_on="$5"   # comma-separated task IDs or empty
    local dir="$META_DIR/$meta_name"

    python3 -c "
import json
with open('$dir/tasks.json') as f:
    data = json.load(f)
data['tasks'] = [t for t in data['tasks'] if t['id'] != '$task_id']
deps = [d.strip() for d in '$depends_on'.split(',') if d.strip()]
data['tasks'].append({
    'id': '$task_id',
    'title': '''$title''',
    'assigned_to': '$assigned_to' or None,
    'status': 'pending',
    'depends_on': deps,
    'created': '$(date -Iseconds)',
    'result': None
})
with open('$dir/tasks.json', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Update task status
meta_update_task() {
    local meta_name="$1"
    local task_id="$2"
    local status="$3"     # pending|in_progress|completed
    local result="$4"     # optional result text
    local dir="$META_DIR/$meta_name"

    python3 -c "
import json
with open('$dir/tasks.json') as f:
    data = json.load(f)
for t in data['tasks']:
    if t['id'] == '$task_id':
        t['status'] = '$status'
        if '''$result''':
            t['result'] = '''$result'''
        break
with open('$dir/tasks.json', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Get team status summary
meta_status() {
    local meta_name="$1"
    local dir="$META_DIR/$meta_name"

    echo "=== META-TEAM: $meta_name ==="
    echo ""
    echo "--- Teams ---"
    python3 -c "
import json
with open('$dir/registry.json') as f:
    reg = json.load(f)
for t in reg['teams']:
    pid_alive = '✓'
    try:
        import os
        os.kill(t['pid'], 0)
    except:
        pid_alive = '✗'
    print(f\"  {t['name']:20s} [{t['status']:8s}] pid={t['pid']} {pid_alive}  role: {t['role']}\")
"
    echo ""
    echo "--- Tasks ---"
    python3 -c "
import json
with open('$dir/tasks.json') as f:
    data = json.load(f)
for t in data['tasks']:
    assigned = t.get('assigned_to') or 'unassigned'
    print(f\"  [{t['status']:12s}] {t['id']:15s} → {assigned:15s} | {t['title']}\")
"
    echo ""
    echo "--- Findings ---"
    local count=0
    for f in "$dir/findings/"*.json; do
        [[ ! -f "$f" ]] && continue
        python3 -c "
import json
with open('$f') as fh:
    finding = json.load(fh)
print(f\"  [{finding['severity']:8s}] {finding['team']:15s} | {finding['title']}\")
"
        ((count++))
    done
    [[ $count -eq 0 ]] && echo "  (none yet)"

    echo ""
    echo "--- Mailbox ---"
    local msg_count
    msg_count=$(ls "$dir/mailbox/"*.json 2>/dev/null | wc -l)
    echo "  $msg_count messages total"
}
