#!/usr/bin/env bash
# setup.sh — FleetCode setup
# Ensures agent teams are enabled, dependencies are met, and everything is ready.
#
# Usage: ./setup.sh
#
# Run this ONCE on a new machine. It:
#   1. Checks claude is installed and version >= 2.1.32
#   2. Enables CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in settings.json
#   3. Checks for gnome-terminal (or finds alternatives)
#   4. Verifies python3 is available
#   5. Makes all scripts executable

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "=== FleetCode Setup ==="
echo ""

ERRORS=0
WARNINGS=0

# 1. Check claude is installed
echo -n "Checking claude... "
if command -v claude &>/dev/null; then
    VERSION=$(claude --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
    echo "found v$VERSION"

    # Check version >= 2.1.32
    REQUIRED="2.1.32"
    if python3 -c "
from packaging.version import Version
import sys
try:
    ok = Version('$VERSION') >= Version('$REQUIRED')
except:
    # packaging not installed, do string comparison
    ok = tuple(int(x) for x in '$VERSION'.split('.')) >= tuple(int(x) for x in '$REQUIRED'.split('.'))
sys.exit(0 if ok else 1)
" 2>/dev/null; then
        echo "  ✓ Version $VERSION >= $REQUIRED (agent teams supported)"
    else
        echo "  ✗ Version $VERSION < $REQUIRED (agent teams need $REQUIRED+)"
        ((ERRORS++))
    fi
else
    echo "NOT FOUND"
    echo "  ✗ Claude Code is required. Install from: https://claude.ai/code"
    ((ERRORS++))
fi

# 2. Enable agent teams in settings.json
echo ""
echo -n "Checking agent teams setting... "
mkdir -p "$HOME/.claude"

if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if already enabled
    CURRENT=$(python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
print(data.get('env', {}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS', ''))
" 2>/dev/null)

    if [[ "$CURRENT" == "1" ]]; then
        echo "already enabled ✓"
    else
        echo "not enabled — enabling now..."
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
if 'env' not in data:
    data['env'] = {}
data['env']['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
print('  ✓ Enabled CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS in settings.json')
"
    fi
else
    echo "no settings.json — creating..."
    cat > "$SETTINGS_FILE" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
EOF
    echo "  ✓ Created $SETTINGS_FILE with agent teams enabled"
fi

# Also set skipDangerousModePermissionPrompt so teams don't stall on permission prompts
SKIP_PERM=$(python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
print(data.get('skipDangerousModePermissionPrompt', False))
" 2>/dev/null)

if [[ "$SKIP_PERM" != "True" ]]; then
    echo -n "  Setting skipDangerousModePermissionPrompt... "
    python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
data['skipDangerousModePermissionPrompt'] = True
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "✓"
fi

# 3. Check terminal emulator
echo ""
echo -n "Checking terminal emulator... "
TERMINAL=""
if command -v gnome-terminal &>/dev/null; then
    TERMINAL="gnome-terminal"
    echo "gnome-terminal ✓"
elif command -v xfce4-terminal &>/dev/null; then
    TERMINAL="xfce4-terminal"
    echo "xfce4-terminal ✓"
elif command -v konsole &>/dev/null; then
    TERMINAL="konsole"
    echo "konsole ✓"
elif command -v xterm &>/dev/null; then
    TERMINAL="xterm"
    echo "xterm ✓"
elif command -v kitty &>/dev/null; then
    TERMINAL="kitty"
    echo "kitty ✓"
elif command -v alacritty &>/dev/null; then
    TERMINAL="alacritty"
    echo "alacritty ✓"
elif command -v wezterm &>/dev/null; then
    TERMINAL="wezterm"
    echo "wezterm ✓"
else
    echo "NONE FOUND"
    echo "  ⚠ No terminal emulator found. Interactive mode won't work."
    echo "    Background mode (--background) will still work."
    echo "    Install one: sudo apt install gnome-terminal"
    ((WARNINGS++))
fi

# Save detected terminal for launch.sh
echo "$TERMINAL" > "$SCRIPT_DIR/.terminal"
echo "  Saved terminal preference: $TERMINAL"

# 4. Check tmux (optional, for split panes)
echo ""
echo -n "Checking tmux (optional)... "
if command -v tmux &>/dev/null; then
    echo "found ✓ (split-pane mode available)"
else
    echo "not found (optional — install for split-pane mode: sudo apt install tmux)"
    ((WARNINGS++))
fi

# 5. Check python3
echo ""
echo -n "Checking python3... "
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version 2>&1)
    echo "$PY_VER ✓"
else
    echo "NOT FOUND"
    echo "  ✗ python3 is required for protocol functions"
    ((ERRORS++))
fi

# 6. Check git
echo ""
echo -n "Checking git... "
if command -v git &>/dev/null; then
    echo "$(git --version) ✓"
else
    echo "NOT FOUND"
    echo "  ✗ git is required (workdirs are initialized as git repos)"
    ((ERRORS++))
fi

# 7. Set teammateMode in ~/.claude.json
echo ""
echo -n "Checking teammateMode in ~/.claude.json... "
CLAUDE_JSON="$HOME/.claude.json"
if [[ -f "$CLAUDE_JSON" ]]; then
    CURRENT_MODE=$(python3 -c "
import json
with open('$CLAUDE_JSON') as f:
    data = json.load(f)
print(data.get('teammateMode', ''))
" 2>/dev/null)
    if [[ -z "$CURRENT_MODE" ]]; then
        python3 -c "
import json
with open('$CLAUDE_JSON') as f:
    data = json.load(f)
data['teammateMode'] = 'in-process'
with open('$CLAUDE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "set to 'in-process' ✓"
    else
        echo "already set to '$CURRENT_MODE' ✓"
    fi
else
    echo '{"teammateMode": "in-process"}' > "$CLAUDE_JSON"
    echo "created with 'in-process' ✓"
fi

# 8. Make all scripts executable
echo ""
echo -n "Setting permissions... "
chmod +x "$SCRIPT_DIR"/{launch.sh,status.sh,send.sh,cleanup.sh,captain.sh}
chmod +x "$SCRIPT_DIR"/hooks/*.sh
chmod +x "$SCRIPT_DIR"/lib/protocol.sh
echo "✓"

# 9. Verify protocol works
echo ""
echo -n "Testing protocol... "
source "$SCRIPT_DIR/lib/protocol.sh"
TEST_DIR=$(meta_init "_setup_test")
meta_send "_setup_test" "setup" "all" "status" "test"
MSG_COUNT=$(ls "$TEST_DIR/mailbox/"*.json 2>/dev/null | wc -l)
rm -rf "$TEST_DIR"
if [[ $MSG_COUNT -eq 1 ]]; then
    echo "✓ (send/receive working)"
else
    echo "✗ (protocol test failed)"
    ((ERRORS++))
fi

# Summary
echo ""
echo "================================"
if [[ $ERRORS -eq 0 ]]; then
    echo "✓ FleetCode is ready!"
    echo ""
    echo "Quick start:"
    echo "  ./launch.sh examples/hunt-layerzero.json    # launch teams in terminals"
    echo "  ./status.sh hunt-lz                         # check progress"
    echo "  source captain.sh hunt-lz                   # become the captain"
else
    echo "✗ $ERRORS error(s) found. Fix them and re-run setup.sh"
fi
if [[ $WARNINGS -gt 0 ]]; then
    echo "  ($WARNINGS warning(s) — optional features unavailable)"
fi
