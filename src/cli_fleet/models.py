"""Per-model launch specs for multi-CLI fleets.

Each supported model maps to:
  - binary:          the executable name
  - headless:        one-shot command template ({prompt} placeholder)
  - interactive:     interactive-session command template ({prompt} placeholder)
  - mailbox_event:   the hook event used to inject cross-team mailbox messages
  - hook_file:       path (relative to the team workdir) of the hook registry
                     that cli-enforcement deploys for this model
  - nested:          True if hook events live under a top-level "hooks" key
                     (settings.json style); False if events sit at the top
                     level of the file (Clawspring hooks.json style)
  - enforce:         cli-enforcement deploy support (all six as of 0.4.0)
  - verified:        True if the headless flags were verified against the
                     installed binary's --help + its cli-wikia wiki. When
                     False the launch prints a warning instead of guessing
                     silently.

Sources: cli-wikia wikis (hooks.md / cli-reference.md / headless*.md per
model, verified 2026-07) plus `<tool> --help` on this machine.
"""
from __future__ import annotations

import json
import os

DEFAULT_MODEL = "claude"

MODEL_SPECS = {
    "claude": {
        "binary": "claude",
        "headless": ["claude", "--dangerously-skip-permissions", "-p", "{prompt}"],
        "interactive": ["claude", "--dangerously-skip-permissions", "{prompt}"],
        "mailbox_event": "UserPromptSubmit",
        "hook_file": os.path.join(".claude", "settings.json"),
        "nested": True,
        "enforce": True,
        "verified": True,  # claude --help + claude wiki cli-reference.md
    },
    "gemini": {
        "binary": "gemini",
        "headless": ["gemini", "--approval-mode", "yolo", "-p", "{prompt}"],
        "interactive": ["gemini", "--approval-mode", "yolo", "-i", "{prompt}"],
        "mailbox_event": "BeforeAgent",  # fires on prompt submit, can inject context
        "hook_file": os.path.join(".gemini", "settings.json"),
        "nested": True,
        "enforce": True,
        "verified": True,  # gemini --help + gemini wiki headless.md
    },
    "deepseek": {
        "binary": "deepseek-code",
        "headless": ["deepseek-code", "--dangerously-skip-permissions", "-p", "{prompt}"],
        "interactive": ["deepseek-code", "--dangerously-skip-permissions", "{prompt}"],
        "mailbox_event": "UserPromptSubmit",  # one of Clawspring's 28 Claude-style events
        "hook_file": os.path.join(".clawspring", "hooks.json"),
        "nested": False,
        "enforce": True,
        "verified": True,  # deepseek-code --help + deepseek wiki cli-reference.md
    },
    "copilot": {
        "binary": "copilot",
        "headless": ["copilot", "--allow-all-tools", "--allow-all-paths", "-p", "{prompt}"],
        "interactive": ["copilot", "--allow-all", "-i", "{prompt}"],
        "mailbox_event": "UserPromptSubmit",  # Claude-format accepted (native: userPromptSubmitted)
        "hook_file": os.path.join(".github", "hooks", "enforcement.json"),
        "nested": True,
        "enforce": True,
        "verified": True,  # copilot --help + copilot wiki cli-reference.md
    },
    "chatgpt": {
        "binary": "codex",
        "headless": ["codex", "exec", "--full-auto", "{prompt}"],
        "interactive": ["codex", "{prompt}"],
        "mailbox_event": "UserPromptSubmit",
        "hook_file": os.path.join(".codex", "hooks.json"),
        "nested": True,
        "enforce": True,
        # codex is not installed here; flags come from the chatgpt wiki
        # (codex-exec.md), which is itself marked "not locally verified".
        "verified": False,
    },
    "antigravity": {
        "binary": "agy",
        "headless": ["agy", "--dangerously-skip-permissions", "-p", "{prompt}"],
        "interactive": ["agy", "--dangerously-skip-permissions", "-i", "{prompt}"],
        "mailbox_event": "PreInvocation",  # fires before each agent turn
        "hook_file": os.path.join(".agents", "hooks.json"),
        "nested": True,
        "enforce": True,
        "verified": True,  # agy --help + antigravity wiki cli-reference.md
    },
}


def spawn_command(model, prompt, mode="background"):
    """Return the argv list to launch `model` with `prompt`."""
    spec = MODEL_SPECS[model]
    template = spec["headless"] if mode == "background" else spec["interactive"]
    return [prompt if a == "{prompt}" else a for a in template]


# --- model-neutral meta-team root -------------------------------------------

def meta_root():
    """Resolve the meta-team root: META_TEAM_DIR env first, then the canonical
    ~/.cli-fleet/meta-teams (symlinked to ~/.claude/meta-teams if that already
    exists, for fleetcode compat)."""
    env = os.environ.get("META_TEAM_DIR")
    if env:
        return env
    return ensure_meta_root()


def ensure_meta_root():
    home = os.path.expanduser("~")
    new = os.path.join(home, ".cli-fleet", "meta-teams")
    old = os.path.join(home, ".claude", "meta-teams")
    if not os.path.lexists(new):
        os.makedirs(os.path.dirname(new), exist_ok=True)
        if os.path.isdir(old):
            os.symlink(old, new)
        else:
            os.makedirs(new, exist_ok=True)
    return new


# --- mailbox hook injection ---------------------------------------------------

def inject_mailbox_hook(team_dir, model, hook_command, timeout=5000):
    """Merge a mailbox-check hook into the model's deployed hook file WITHOUT
    clobbering the enforcement hooks cli-enforcement just wrote. Returns the
    hook file path, or None if the model has no mailbox hook event."""
    spec = MODEL_SPECS[model]
    event = spec["mailbox_event"]
    if not event:
        return None
    path = os.path.join(team_dir, spec["hook_file"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        data = {}
    if spec["nested"]:
        events = data.setdefault("hooks", {})
    else:
        events = data
    groups = events.setdefault(event, [])
    present = {
        h.get("command")
        for g in groups if isinstance(g, dict)
        for h in g.get("hooks", [])
        if isinstance(h, dict)
    }
    if hook_command not in present:
        groups.append({
            "hooks": [{"type": "command", "command": hook_command, "timeout": timeout}]
        })
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    return path
