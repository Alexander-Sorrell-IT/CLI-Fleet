"""Hermetic tests for multi-CLI fleet support — no real sessions, stub binaries."""
import json
import os
import stat
import subprocess

import pytest

from cli_fleet import cli, models as M

# Models that have full fleet support (headless launch + mailbox + enforcement)
FLEET_MODELS = ["claude", "gemini", "deepseek", "copilot", "chatgpt", "antigravity"]
ALL_MODELS = FLEET_MODELS  # backward compat alias
SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "src", "cli_fleet", "scripts")


# --- MODEL_SPECS shape --------------------------------------------------------

def test_model_specs_fleet_models_present():
    """All six original fleet-capable models are still in MODEL_SPECS."""
    for m in FLEET_MODELS:
        assert m in M.MODEL_SPECS, f"missing fleet model: {m}"


@pytest.mark.parametrize("model", FLEET_MODELS)
def test_model_spec_shape(model):
    spec = M.MODEL_SPECS[model]
    for key in ("binary", "headless", "interactive", "mailbox_event",
                "hook_file", "nested", "enforce", "verified"):
        assert key in spec, f"{model} missing {key}"
    assert spec["headless"] is not None, f"{model} has no headless template"
    assert spec["headless"][0] == spec["binary"]
    assert "{prompt}" in spec["headless"]
    assert isinstance(spec["nested"], bool)
    assert spec["enforce"] is True
    assert isinstance(spec["verified"], bool)


def test_expected_mailbox_events():
    assert M.MODEL_SPECS["claude"]["mailbox_event"] == "UserPromptSubmit"
    assert M.MODEL_SPECS["gemini"]["mailbox_event"] == "BeforeAgent"
    assert M.MODEL_SPECS["deepseek"]["mailbox_event"] == "UserPromptSubmit"
    assert M.MODEL_SPECS["copilot"]["mailbox_event"] == "UserPromptSubmit"
    assert M.MODEL_SPECS["chatgpt"]["mailbox_event"] == "UserPromptSubmit"
    assert M.MODEL_SPECS["antigravity"]["mailbox_event"] == "PreInvocation"


def test_chatgpt_marked_unverified():
    assert M.MODEL_SPECS["chatgpt"]["verified"] is False


# --- spawn command construction ----------------------------------------------

def test_spawn_command_substitutes_prompt():
    cmd = M.spawn_command("claude", "do the thing", mode="background")
    assert cmd == ["claude", "--dangerously-skip-permissions", "-p", "do the thing"]
    cmd = M.spawn_command("gemini", "hi", mode="interactive")
    assert cmd == ["gemini", "--approval-mode", "yolo", "-i", "hi"]


@pytest.mark.parametrize("model", ALL_MODELS)
def test_launch_sh_spawn_matches_python_spec(model, tmp_path):
    """launch.sh's model_spawn_cmd must mirror MODEL_SPECS headless templates."""
    for mode in ("background", "interactive"):
        out = subprocess.run(
            ["bash", "-c",
             f'source /dev/stdin <<<"$(sed -n \'/^model_spawn_cmd()/,/^}}/p\' '
             f'{SCRIPTS}/launch.sh)"; model_spawn_cmd {model} {mode}'],
            capture_output=True, text=True,
        )
        prefix = out.stdout.strip().split()
        expected = M.spawn_command(model, "PROMPT", mode=mode)
        assert expected[-1] == "PROMPT"
        assert prefix == expected[:-1], f"{model}/{mode}: {prefix} != {expected[:-1]}"


def _stub_bin(dir_, name):
    p = dir_ / name
    p.write_text(f'#!/usr/bin/env bash\necho "STUB {name} $@"\n'
                 f'echo "{name} $@" >> "{dir_}/calls.log"\n')
    p.chmod(p.stat().st_mode | stat.S_IEXEC)
    return p


def test_launch_sh_spawns_stub_binaries_per_model(tmp_path, monkeypatch):
    """End-to-end --background launch with a mixed config against stub CLIs."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    for b in ("claude", "gemini", "deepseek-code", "cli-enforcement"):
        _stub_bin(bindir, b)
    root = tmp_path / "meta-teams"
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")

    cfg = {
        "meta_team": "mix", "project_dir": str(tmp_path),
        "teams": [
            {"name": "t-claude", "role": "r", "task": "task a"},
            {"name": "t-gemini", "role": "r", "task": "task b", "model": "gemini"},
            {"name": "t-deepseek", "role": "r", "task": "task c", "model": "deepseek"},
        ],
    }
    cfg_path = tmp_path / "cfg.json"
    cfg_path.write_text(json.dumps(cfg))

    proc = subprocess.run(
        ["bash", os.path.join(SCRIPTS, "launch.sh"), str(cfg_path), "--background"],
        capture_output=True, text=True, timeout=120,
    )
    assert proc.returncode == 0, proc.stderr
    calls = (bindir / "calls.log").read_text()
    assert "claude --dangerously-skip-permissions -p task a" in calls
    assert "gemini --approval-mode yolo -p task b" in calls
    assert "deepseek-code --dangerously-skip-permissions -p task c" in calls

    registry = json.loads((root / "mix" / "registry.json").read_text())
    by_name = {t["name"]: t for t in registry["teams"]}
    assert by_name["t-claude"]["model"] == "claude"
    assert by_name["t-gemini"]["model"] == "gemini"
    assert by_name["t-deepseek"]["model"] == "deepseek"


# --- meta-team root resolution -------------------------------------------------

def test_meta_root_env_override(tmp_path, monkeypatch):
    monkeypatch.setenv("META_TEAM_DIR", str(tmp_path / "custom"))
    assert M.meta_root() == str(tmp_path / "custom")


def test_meta_root_symlinks_legacy_dir(tmp_path, monkeypatch):
    home = tmp_path / "home"
    legacy = home / ".claude" / "meta-teams"
    legacy.mkdir(parents=True)
    (legacy / "old-team").mkdir()
    monkeypatch.delenv("META_TEAM_DIR", raising=False)
    monkeypatch.setenv("HOME", str(home))
    root = M.meta_root()
    assert root == str(home / ".cli-fleet" / "meta-teams")
    assert os.path.islink(root)
    assert os.path.isdir(os.path.join(root, "old-team"))  # reads old path transparently


def test_meta_root_fresh_dir_when_no_legacy(tmp_path, monkeypatch):
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.delenv("META_TEAM_DIR", raising=False)
    monkeypatch.setenv("HOME", str(home))
    root = M.meta_root()
    assert os.path.isdir(root) and not os.path.islink(root)


# --- mixed-fleet prepare: per-team deploy calls ---------------------------------

def test_prepare_teams_deploys_per_model(tmp_path, monkeypatch, capsys):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    _stub_bin(bindir, "cli-enforcement")
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    root = tmp_path / "meta-teams"
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))

    cfg = {
        "meta_team": "mix",
        "teams": [
            {"name": "t-claude", "role": "r", "task": "x"},
            {"name": "t-gemini", "role": "r", "task": "x", "model": "gemini"},
            {"name": "t-deepseek", "role": "r", "task": "x", "model": "deepseek"},
        ],
    }
    cli._prepare_teams(cfg)
    calls = (bindir / "calls.log").read_text().strip().splitlines()
    wd = root / "mix" / "workdirs"
    assert f"cli-enforcement deploy claude --dir {wd}/t-claude --write" in calls
    assert f"cli-enforcement deploy gemini --dir {wd}/t-gemini --write" in calls
    assert f"cli-enforcement deploy deepseek --dir {wd}/t-deepseek --write" in calls
    # non-claude teams got a mailbox hook in their model's hook file
    gem = json.loads((wd / "t-gemini" / ".gemini" / "settings.json").read_text())
    assert "BeforeAgent" in gem["hooks"]
    dsk = json.loads((wd / "t-deepseek" / ".clawspring" / "hooks.json").read_text())
    assert "UserPromptSubmit" in dsk
    # claude gets its mailbox hook from launch.sh, not here
    assert not (wd / "t-claude" / ".claude" / "settings.json").exists()


def test_prepare_teams_unknown_model_exits(tmp_path, monkeypatch):
    monkeypatch.setenv("META_TEAM_DIR", str(tmp_path / "mt"))
    cfg = {"meta_team": "x", "teams": [{"name": "t", "model": "notreal"}]}
    with pytest.raises(SystemExit) as exc:
        cli._prepare_teams(cfg, enforce=False)
    assert "notreal" in str(exc.value)


def test_prepare_teams_warns_unverified(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("META_TEAM_DIR", str(tmp_path / "mt"))
    cfg = {"meta_team": "x", "teams": [{"name": "t-gpt", "model": "chatgpt"}]}
    cli._prepare_teams(cfg, enforce=False)
    out = capsys.readouterr().out
    assert "NOT verified" in out


# --- hook injection merges without clobbering ------------------------------------

def test_inject_mailbox_hook_preserves_enforcement(tmp_path):
    team_dir = tmp_path / "team"
    hook_path = team_dir / ".gemini" / "settings.json"
    hook_path.parent.mkdir(parents=True)
    enforcement = {
        "hooks": {
            "BeforeTool": [{"matcher": ".*", "hooks": [
                {"type": "command", "command": "python3 enforce.py pre"}]}],
            "BeforeAgent": [{"hooks": [
                {"type": "command", "command": "python3 enforce.py prompt"}]}],
        }
    }
    hook_path.write_text(json.dumps(enforcement))

    path = M.inject_mailbox_hook(str(team_dir), "gemini", "bash check-mailbox.sh")
    data = json.loads(hook_path.read_text())
    assert path == str(hook_path)
    # enforcement hooks untouched
    assert data["hooks"]["BeforeTool"] == enforcement["hooks"]["BeforeTool"]
    cmds = [h["command"] for g in data["hooks"]["BeforeAgent"] for h in g["hooks"]]
    assert "python3 enforce.py prompt" in cmds
    assert "bash check-mailbox.sh" in cmds
    # idempotent
    M.inject_mailbox_hook(str(team_dir), "gemini", "bash check-mailbox.sh")
    data2 = json.loads(hook_path.read_text())
    assert data2 == data


def test_inject_mailbox_hook_flat_schema_deepseek(tmp_path):
    team_dir = tmp_path / "team"
    M.inject_mailbox_hook(str(team_dir), "deepseek", "bash mb.sh")
    data = json.loads((team_dir / ".clawspring" / "hooks.json").read_text())
    assert "hooks" not in data  # flat: events at top level
    assert data["UserPromptSubmit"][0]["hooks"][0]["command"] == "bash mb.sh"


# --- dashboard model column ---------------------------------------------------

def test_dashboard_shows_model(tmp_path, monkeypatch):
    root = tmp_path / "meta-teams"
    dir_ = root / "mix"
    for sub in ("mailbox", "findings", "status"):
        (dir_ / sub).mkdir(parents=True)
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    registry = {"meta_team": "mix", "teams": [
        {"name": "t-gem", "role": "r", "pid": 1, "workdir": "", "status": "active",
         "model": "gemini"},
        {"name": "t-old", "role": "r", "pid": 1, "workdir": "", "status": "active"},
    ]}
    (dir_ / "registry.json").write_text(json.dumps(registry))
    data = cli.gather_dashboard("mix")
    by_name = {t["name"]: t for t in data["teams"]}
    assert by_name["t-gem"]["model"] == "gemini"
    assert by_name["t-old"]["model"] == "claude"  # legacy entries default
    out = cli.render_dashboard(data)
    assert "gemini" in out
