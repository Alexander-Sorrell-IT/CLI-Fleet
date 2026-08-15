#!/usr/bin/env bash
# FleetCode — launch.sh
# Creates N team leads, each in its own terminal window, fully interactive.
#
# Usage:
#   ./launch.sh <config.json>
#   ./launch.sh <config.json> --background   # use claude -p instead of terminals
#   ./launch.sh --example                    # print example config
#
# Run setup.sh first to enable agent teams and detect your terminal emulator.
#
# Each team gets:
#   - Its own terminal window (gnome-terminal, xfce4-terminal, konsole, kitty, etc.)
#   - A generated CLAUDE.md with cross-team protocol
#   - A UserPromptSubmit hook that injects cross-team messages
#   - An initial prompt sent to claude as first argument

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
META_DIR="${META_TEAM_DIR:-$HOME/.cli-fleet/meta-teams}"
# (protocol.sh, sourced below, re-resolves META_DIR and creates the
#  ~/.cli-fleet/meta-teams root / legacy symlink on first use)

print_example() {
    cat <<'EXAMPLE'
{
  "meta_team": "hunt-lz",
  "project_dir": "/media/phantom-orchestrator/Elements1/Ubuntu/bounty-recon",
  "teams": [
    {
      "name": "team-evm-v1",
      "role": "Hunt V1 EVM contracts — UltraLightNodeV2, Endpoint V1, FPValidator ($15M cap)",
      "teammates": 3,
      "task": "Create an agent team with 3 teammates. Focus on V1 EVM contracts worth $15M each. Run hunt-auto evm on UltraLightNodeV2, Endpoint V1, and FPValidator. Chase every finding. Post bugs to the cross-team mailbox."
    },
    {
      "name": "team-evm-v2",
      "role": "Hunt V2 EVM contracts — EndpointV2, SendULN302, ReceiveULN302, DVN ($2M cap)",
      "teammates": 3,
      "task": "Create an agent team with 3 teammates. Focus on V2 EVM protocol contracts. Run hunt-auto evm on EndpointV2, SendULN302, ReceiveULN302, DVN. Focus on cross-contract interactions."
    },
    {
      "name": "team-crosschain",
      "role": "Hunt cross-chain exploit chains — EVM↔Solana, EVM↔TON, encoding mismatches ($2M-$15M)",
      "teammates": 4,
      "task": "Create an agent team with 4 teammates. Focus ONLY on cross-chain attack vectors: address encoding mismatches, nonce desync, executor gas model differences, composed message multi-hop. Use xchain-abi-check, xchain-fuzz, xchain-tracer."
    },
    {
      "name": "team-non-evm",
      "role": "Hunt Solana + TON + Aptos contracts ($2M cap)",
      "teammates": 3,
      "task": "Create an agent team with 3 teammates. One on Solana (DVN, Endpoint, ULN, OFT), one on TON (Controller, ULNManager, DVNProxy), one on Aptos (Endpoint). Run hunt-auto for each chain."
    }
  ]
}
EXAMPLE
}

if [[ "${1:-}" == "--example" ]]; then
    print_example
    exit 0
fi

CONFIG="${1:?Usage: $0 <config.json> [--background] | $0 --example}"
[[ ! -f "$CONFIG" ]] && echo "Error: config file not found: $CONFIG" && exit 1

MODE="interactive"
[[ "${2:-}" == "--background" ]] && MODE="background"

# Per-model spawn command (mirrors cli_fleet/models.py MODEL_SPECS).
# Prints the command *prefix*; the caller appends the prompt as the last arg.
# $1 = model, $2 = mode (interactive|background)
model_spawn_cmd() {
    local model="$1" mode="$2"
    case "$model" in
        claude)
            if [[ "$mode" == "background" ]]; then echo "claude --dangerously-skip-permissions -p"
            else echo "claude --dangerously-skip-permissions"; fi ;;
        gemini)
            if [[ "$mode" == "background" ]]; then echo "gemini --approval-mode yolo -p"
            else echo "gemini --approval-mode yolo -i"; fi ;;
        deepseek)
            if [[ "$mode" == "background" ]]; then echo "deepseek-code --dangerously-skip-permissions -p"
            else echo "deepseek-code --dangerously-skip-permissions"; fi ;;
        copilot)
            if [[ "$mode" == "background" ]]; then echo "copilot --allow-all-tools --allow-all-paths -p"
            else echo "copilot --allow-all -i"; fi ;;
        chatgpt)
            # NOT verified locally (codex not installed) — flags from the chatgpt wiki.
            if [[ "$mode" == "background" ]]; then echo "codex exec --full-auto"
            else echo "codex"; fi ;;
        antigravity)
            if [[ "$mode" == "background" ]]; then echo "agy --dangerously-skip-permissions -p"
            else echo "agy --dangerously-skip-permissions -i"; fi ;;
        *)
            echo "" ;;
    esac
}

# Parse config
META_TEAM=$(python3 -c "import json; print(json.load(open('$CONFIG'))['meta_team'])")
PROJECT_DIR=$(python3 -c "import json; print(json.load(open('$CONFIG'))['project_dir'])")
NUM_TEAMS=$(python3 -c "import json; print(len(json.load(open('$CONFIG'))['teams']))")

echo "=== Multi-Team Launcher ==="
echo "Meta-team:   $META_TEAM"
echo "Project dir: $PROJECT_DIR"
echo "Teams:       $NUM_TEAMS"
echo "Mode:        $MODE"
echo ""

# Step 1: Initialize shared state
source "$SCRIPT_DIR/lib/protocol.sh"
SHARED_DIR=$(meta_init "$META_TEAM")
echo "Shared state: $SHARED_DIR"
mkdir -p "$SHARED_DIR/logs"

# Step 2: Build team roster for CLAUDE.md template
ROSTER=""
for i in $(seq 0 $((NUM_TEAMS - 1))); do
    t_name=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i]['name'])")
    t_role=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i]['role'])")
    ROSTER+="- **${t_name}**: ${t_role}"$'\n'
done

# Step 3: Create per-team working directories and launch
PIDS=()
for i in $(seq 0 $((NUM_TEAMS - 1))); do
    TEAM_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i]['name'])")
    TEAM_ROLE=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i]['role'])")
    TEAM_TASK=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i]['task'])")
    TEAM_MATES=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i].get('teammates', 3))")
    TEAM_MODE=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i].get('mode', 'standard'))")
    TEAM_MODEL=$(python3 -c "import json; print(json.load(open('$CONFIG'))['teams'][$i].get('model', 'claude'))")

    echo ""
    echo "--- Setting up $TEAM_NAME ---"
    echo "  Role: $TEAM_ROLE"
    echo "  Teammates: $TEAM_MATES"
    echo "  Mode: $TEAM_MODE"
    echo "  Model: $TEAM_MODEL"

    # Create team workdir
    TEAM_DIR="$SHARED_DIR/workdirs/$TEAM_NAME"
    mkdir -p "$TEAM_DIR"

    # Per-team consciousness file for brain-stream mode
    CONSCIOUSNESS_FILE="$TEAM_DIR/consciousness.md"

    # Select template based on mode
    if [[ "$TEAM_MODE" == "brain-stream" ]]; then
        TEMPLATE="$SCRIPT_DIR/templates/brain-stream-lead.md"
    else
        TEMPLATE="$SCRIPT_DIR/templates/team-lead.md"
    fi

    # Generate CLAUDE.md from template
    TEAM_CLAUDE="$TEAM_DIR/CLAUDE.md"
    sed \
        -e "s|{{TEAM_NAME}}|$TEAM_NAME|g" \
        -e "s|{{META_TEAM}}|$META_TEAM|g" \
        -e "s|{{ROLE}}|$TEAM_ROLE|g" \
        -e "s|{{META_DIR}}|$SHARED_DIR|g" \
        -e "s|{{MULTI_TEAM_DIR}}|$SCRIPT_DIR|g" \
        -e "s|{{TASK}}|$TEAM_TASK|g" \
        -e "s|{{CONSCIOUSNESS_FILE}}|$CONSCIOUSNESS_FILE|g" \
        "$TEMPLATE" > "$TEAM_CLAUDE"

    # Replace roster (multiline — use python)
    python3 -c "
content = open('$TEAM_CLAUDE').read()
content = content.replace('{{TEAM_ROSTER}}', '''$ROSTER''')
open('$TEAM_CLAUDE', 'w').write(content)
"

    # Copy project CLAUDE.md so teams get project context
    if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
        cp "$PROJECT_DIR/CLAUDE.md" "$TEAM_DIR/PROJECT_CLAUDE.md"
    fi

    # Initialize workdir as a git repo so claude trusts it without prompting
    (cd "$TEAM_DIR" && git init -q 2>/dev/null && git commit --allow-empty -m "init" -q 2>/dev/null) || true

    # Create project-level settings.json with hooks based on mode.
    # Claude teams only — other models get their mailbox hook merged into
    # their own hook file (.gemini/settings.json, .clawspring/hooks.json, …)
    # by `cli-fleet launch` before this script runs.
    if [[ "$TEAM_MODEL" == "claude" ]]; then
    mkdir -p "$TEAM_DIR/.claude"
    FLEET_SETTINGS="$TEAM_DIR/.claude/settings.fleet.json"

    # Brain-stream mode gets the consciousness bridge + stall detection
    # Standard mode gets the regular mailbox + task hooks
    if [[ "$TEAM_MODE" == "brain-stream" ]]; then
        cat > "$FLEET_SETTINGS" <<SETTINGS
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "META_TEAM_NAME": "$META_TEAM",
    "TEAM_NAME": "$TEAM_NAME",
    "META_TEAM_DIR": "$META_DIR",
    "CONSCIOUSNESS_FILE": "$CONSCIOUSNESS_FILE"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/check-mailbox.sh",
            "timeout": 5000
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/consciousness-bridge.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/stream-stall-check.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS
    else
        cat > "$FLEET_SETTINGS" <<STDSETTINGS
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "META_TEAM_NAME": "$META_TEAM",
    "TEAM_NAME": "$TEAM_NAME",
    "META_TEAM_DIR": "$META_DIR"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/check-mailbox.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/teammate-idle.sh"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash $SCRIPT_DIR/hooks/task-completed.sh"
          }
        ]
      }
    ]
  }
}
STDSETTINGS
    fi

    # Merge the fleet settings into any existing settings.json (e.g. the one
    # cli-enforcement just deployed) instead of clobbering it.
    python3 - "$TEAM_DIR/.claude/settings.json" "$FLEET_SETTINGS" <<'MERGE'
import json, os, sys
dst_path, src_path = sys.argv[1], sys.argv[2]
with open(src_path) as f:
    src = json.load(f)
try:
    with open(dst_path) as f:
        dst = json.load(f)
except (OSError, json.JSONDecodeError):
    dst = {}
dst.setdefault("env", {}).update(src.get("env", {}))
hooks = dst.setdefault("hooks", {})
for event, groups in src.get("hooks", {}).items():
    cur = hooks.setdefault(event, [])
    present = {h.get("command") for g in cur for h in g.get("hooks", [])}
    for g in groups:
        if not ({h.get("command") for h in g.get("hooks", [])} & present):
            cur.append(g)
with open(dst_path, "w") as f:
    json.dump(dst, f, indent=2)
MERGE
    rm -f "$FLEET_SETTINGS"
    fi  # TEAM_MODEL == claude

    # Install subagent definitions so leads can spawn typed teammates
    mkdir -p "$TEAM_DIR/.claude/agents"
    for agent_def in "$SCRIPT_DIR"/agents/*.md; do
        [[ -f "$agent_def" ]] && cp "$agent_def" "$TEAM_DIR/.claude/agents/"
    done

    # Fill in placeholders in the agent definitions
    for agent_file in "$TEAM_DIR/.claude/agents/"*.md; do
        [[ -f "$agent_file" ]] && python3 -c "
import sys
p = sys.argv[1]
t = open(p).read()
t = t.replace('{{CONSCIOUSNESS_FILE}}', sys.argv[2])
t = t.replace('{{MULTI_TEAM_DIR}}',     sys.argv[3])
t = t.replace('{{META_TEAM}}',          sys.argv[4])
t = t.replace('{{TEAM_NAME}}',          sys.argv[5])
open(p, 'w').write(t)
" "$agent_file" "$CONSCIOUSNESS_FILE" "$SCRIPT_DIR" "$META_TEAM" "$TEAM_NAME"
    done

    # Build the initial prompt based on mode
    if [[ "$TEAM_MODE" == "brain-stream" ]]; then
        INIT_PROMPT="$TEAM_TASK

THIS IS A BRAIN STREAM. You are the PACEMAKER.
1. Initialize the consciousness file at: $CONSCIOUSNESS_FILE
2. Spawn neurons using the brain-neuron agent type
3. DO NOT create tasks — neurons self-direct
4. Read your CLAUDE.md for full brain stream protocol
5. Bridge critical findings to the FleetCode mailbox for other brains

IMPORTANT CONTEXT:
- You are $TEAM_NAME in the $META_TEAM fleet"
    else
        INIT_PROMPT="$TEAM_TASK

IMPORTANT CONTEXT:
- You are $TEAM_NAME in the $META_TEAM multi-team operation
- Read your CLAUDE.md for cross-team mailbox protocol
- Other teams running in parallel: check $SHARED_DIR/registry.json
- Post all findings to the shared mailbox immediately
- Check mailbox for messages from other teams after each task"
    fi

    # Write the prompt to a file so we can pass it cleanly (avoids shell escaping hell)
    PROMPT_FILE="$SHARED_DIR/logs/${TEAM_NAME}.prompt"
    echo "$INIT_PROMPT" > "$PROMPT_FILE"

    LOG_FILE="$SHARED_DIR/logs/${TEAM_NAME}.log"

    SPAWN_CMD=$(model_spawn_cmd "$TEAM_MODEL" "$MODE")
    if [[ -z "$SPAWN_CMD" ]]; then
        echo "  ERROR: unknown model '$TEAM_MODEL' for $TEAM_NAME — skipping."
        continue
    fi
    if ! command -v "${SPAWN_CMD%% *}" &>/dev/null; then
        echo "  WARNING: '${SPAWN_CMD%% *}' not found on PATH — $TEAM_NAME may fail to start."
    fi

    if [[ "$MODE" == "interactive" ]]; then
        # Launch in a real terminal window — fully interactive claude session
        echo "  Opening terminal window for $TEAM_NAME..."

        # Detect terminal emulator
        TERMINAL=""
        if [[ -f "$SCRIPT_DIR/.terminal" ]]; then
            TERMINAL=$(cat "$SCRIPT_DIR/.terminal")
        fi
        # Fallback detection if setup.sh wasn't run
        if [[ -z "$TERMINAL" ]]; then
            for t in gnome-terminal xfce4-terminal konsole kitty alacritty wezterm xterm; do
                if command -v "$t" &>/dev/null; then
                    TERMINAL="$t"
                    break
                fi
            done
        fi
        if [[ -z "$TERMINAL" ]]; then
            echo "  ERROR: No terminal emulator found. Run setup.sh or use --background"
            exit 1
        fi

        # Write a launcher script for this team
        LAUNCHER="$SHARED_DIR/logs/${TEAM_NAME}-launcher.sh"
        cat > "$LAUNCHER" <<LAUNCH
#!/usr/bin/env bash
export META_TEAM_NAME="$META_TEAM"
export TEAM_NAME="$TEAM_NAME"
export META_TEAM_DIR="$META_DIR"
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"
cd "$PROJECT_DIR"

# Log PID for tracking
echo \$\$ > "$SHARED_DIR/logs/${TEAM_NAME}.pid"

# Source protocol for completion message
source "$SCRIPT_DIR/lib/protocol.sh"
meta_register_team "$META_TEAM" "$TEAM_NAME" "$TEAM_ROLE" \$\$ "$TEAM_DIR" "$TEAM_MODEL"

# Launch interactive session ($TEAM_MODEL) from project dir
INIT_MSG=\$(cat "$PROMPT_FILE")
$SPAWN_CMD "\$INIT_MSG"

# On exit, notify other teams
meta_send "$META_TEAM" "$TEAM_NAME" "all" "status" "$TEAM_NAME session ended"
LAUNCH
        chmod +x "$LAUNCHER"

        # Open terminal with the launcher — supports multiple emulators
        case "$TERMINAL" in
            gnome-terminal)
                gnome-terminal --title="$TEAM_NAME — $META_TEAM" \
                    --geometry=120x40 \
                    -- bash "$LAUNCHER" &
                ;;
            xfce4-terminal)
                xfce4-terminal --title="$TEAM_NAME — $META_TEAM" \
                    --geometry=120x40 \
                    -e "bash $LAUNCHER" &
                ;;
            konsole)
                konsole --title "$TEAM_NAME — $META_TEAM" \
                    -e bash "$LAUNCHER" &
                ;;
            kitty)
                kitty --title "$TEAM_NAME — $META_TEAM" \
                    bash "$LAUNCHER" &
                ;;
            alacritty)
                alacritty --title "$TEAM_NAME — $META_TEAM" \
                    -e bash "$LAUNCHER" &
                ;;
            wezterm)
                wezterm start --cwd "$TEAM_DIR" \
                    -- bash "$LAUNCHER" &
                ;;
            xterm)
                xterm -title "$TEAM_NAME — $META_TEAM" \
                    -geometry 120x40 \
                    -e bash "$LAUNCHER" &
                ;;
            *)
                echo "  Unknown terminal: $TERMINAL — falling back to background mode"
                MODE="background"
                ;;
        esac

        if [[ "$MODE" == "interactive" ]]; then
            TERM_PID=$!
            PIDS+=("$TERM_PID")
            echo "  Terminal ($TERMINAL) PID: $TERM_PID"
        fi
    fi

    if [[ "$MODE" == "background" ]]; then
        # Background mode — headless one-shot, no terminal window
        echo "  Launching background $TEAM_MODEL session (log: $LOG_FILE)..."

        (
            export META_TEAM_NAME="$META_TEAM"
            export TEAM_NAME="$TEAM_NAME"
            export META_TEAM_DIR="$META_DIR"
            export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"
            cd "$TEAM_DIR"

            source "$SCRIPT_DIR/lib/protocol.sh"
            meta_register_team "$META_TEAM" "$TEAM_NAME" "$TEAM_ROLE" $$ "$TEAM_DIR" "$TEAM_MODEL"

            $SPAWN_CMD "$(cat "$PROMPT_FILE")" \
                > "$LOG_FILE" 2>&1

            meta_send "$META_TEAM" "$TEAM_NAME" "all" "status" "$TEAM_NAME completed its task"
        ) &

        TEAM_PID=$!
        PIDS+=("$TEAM_PID")
        echo "  PID: $TEAM_PID"
    fi
done

echo ""
echo "=== All $NUM_TEAMS teams launched ($MODE mode) ==="
echo ""
echo "Monitor:"
echo "  $SCRIPT_DIR/status.sh $META_TEAM"
echo ""
echo "Send message to a team:"
echo "  $SCRIPT_DIR/send.sh $META_TEAM coordinator <team-name|all> <type> \"<content>\""
echo ""
if [[ "$MODE" == "background" ]]; then
    echo "View logs:"
    echo "  tail -f $SHARED_DIR/logs/*.log"
    echo ""
fi
echo "Cleanup:"
echo "  $SCRIPT_DIR/cleanup.sh $META_TEAM"
echo ""

# Save PIDs for cleanup
printf '%s\n' "${PIDS[@]}" > "$SHARED_DIR/pids.txt"

echo "PIDs saved to $SHARED_DIR/pids.txt"

if [[ "$MODE" == "interactive" ]]; then
    echo ""
    echo "Each team is running in its own terminal window."
    echo "You can type directly into any team's terminal."
    echo "Teams communicate via: $SHARED_DIR/mailbox/"
fi
