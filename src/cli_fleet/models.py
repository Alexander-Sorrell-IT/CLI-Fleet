"""Per-model launch specs for multi-CLI fleets.

MODEL_SPECS is now derived from models.json (cli-fleet) via the registry so
adding a model means editing one file. When cli-collective is installed its
models.json acts as an override layer. The dict is kept for backward compat
with code that does MODEL_SPECS[model][field].

Sources: cli-wikia wikis + `<tool> --help` — see each model entry in
cli-fleet/src/cli_fleet/models.json and cli-enforcement/src/cli_enforcement/models.json.
"""
from __future__ import annotations

import json
import os

from . import registry as _reg

DEFAULT_MODEL = "claude"


def _build_model_specs():
    """Build MODEL_SPECS from the fleet registry, adding hook_file/nested from
    the enforcement registry when available (falls back to registry.hook_file_for)."""
    specs = {}
    for m in _reg.all_models():
        d = _reg.model_data(m)
        # hook_file / nested come from enforcement registry when installed
        hf = _reg.hook_file_for(m)
        try:
            from cli_enforcement.registry import hook_file_spec
            _, nested = hook_file_spec(m)
        except ImportError:
            nested = True
        specs[m] = {
            "binary": d.get("binary"),
            "headless": d.get("headless"),
            "interactive": d.get("interactive"),
            "mailbox_event": d.get("mailbox_event"),
            "hook_file": hf,
            "nested": nested,
            "enforce": d.get("enforce", False),
            "verified": d.get("verified", False),
        }
    return specs


MODEL_SPECS = _build_model_specs()


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
