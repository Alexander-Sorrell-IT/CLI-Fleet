"""Model registry loader for cli-fleet.

Reads models.json (bundled with this package) and, when cli-collective is
installed, deep-merges the collective override on top.

Usage:
    from cli_fleet.registry import get, all_models, spawn_command, hook_file_for
"""
from __future__ import annotations

import copy
import json
import os
from importlib import resources
from typing import Any, Dict, List, Optional


def _load_bundled() -> Dict[str, Any]:
    text = (resources.files("cli_fleet") / "models.json").read_text(encoding="utf-8")
    return json.loads(text)


def _load_collective_override() -> Optional[Dict[str, Any]]:
    """Load the 'fleet' sub-dict from cli-collective's models.json, if present."""
    try:
        from importlib import resources as _r
        text = (_r.files("cli_collective") / "models.json").read_text(encoding="utf-8")
        data = json.loads(text)
        return data.get("fleet") or None
    except Exception:
        return None


def _deep_merge(base: Dict, override: Dict) -> Dict:
    result = copy.deepcopy(base)
    for key, val in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = _deep_merge(result[key], val)
        else:
            result[key] = copy.deepcopy(val)
    return result


def _build_registry() -> Dict[str, Any]:
    data = _load_bundled()
    override = _load_collective_override()
    if override:
        over_models = override.get("models", {})
        if over_models:
            data["models"] = _deep_merge(data.get("models", {}), over_models)
    return data


_REGISTRY: Dict[str, Any] = _build_registry()


def all_models() -> List[str]:
    return list(_REGISTRY.get("models", {}).keys())


def model_data(model: str) -> Dict[str, Any]:
    return _REGISTRY.get("models", {}).get(model, {})


def get(model: str, field: str, default: Any = None) -> Any:
    return model_data(model).get(field, default)


def spawn_command(model: str, prompt: str, mode: str = "background") -> Optional[List[str]]:
    """Return the argv list to launch `model` with `prompt`, or None if unsupported."""
    d = model_data(model)
    template = d.get("headless") if mode == "background" else d.get("interactive")
    if not template:
        return None
    return [prompt if a == "{prompt}" else a for a in template]


def hook_file_for(model: str) -> Optional[str]:
    """Hook file path (relative to team workdir) from cli-enforcement registry, or
    a best-effort fallback from cli-wikia. Returns None when neither is available."""
    # Prefer enforcement registry (more authoritative for hook file location)
    try:
        from cli_enforcement.registry import hook_file_spec
        hf, _ = hook_file_spec(model)
        return hf
    except ImportError:
        pass
    # Fallback: derive from cli-wikia config_root + a conventional filename
    try:
        from cli_wikia.registry import config_root
        root = config_root(model)
        if root:
            return os.path.join(root, "settings.json")
    except ImportError:
        pass
    return None


def mailbox_event(model: str) -> Optional[str]:
    return get(model, "mailbox_event")


def is_verified(model: str) -> bool:
    return bool(get(model, "verified", False))


def can_enforce(model: str) -> bool:
    return bool(get(model, "enforce", False))


def reload() -> None:
    global _REGISTRY
    _REGISTRY = _build_registry()
