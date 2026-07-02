"""Hermetic tests for cli_fleet.cli — no network, no real ~/.claude."""
import os

import pytest

from cli_fleet import cli


def _make_meta_root(tmp_path, monkeypatch, teams):
    root = tmp_path / "meta-teams"
    for name in teams:
        (root / name).mkdir(parents=True)
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    return root


def test_resolve_team_explicit_wins(tmp_path, monkeypatch):
    _make_meta_root(tmp_path, monkeypatch, ["a", "b"])
    assert cli._resolve_team("chosen") == "chosen"


def test_resolve_team_single_autodetected(tmp_path, monkeypatch):
    _make_meta_root(tmp_path, monkeypatch, ["only-team"])
    assert cli._resolve_team(None) == "only-team"


def test_resolve_team_none_exits(tmp_path, monkeypatch):
    root = _make_meta_root(tmp_path, monkeypatch, [])
    root.mkdir(exist_ok=True)  # empty root exists but no team dirs
    with pytest.raises(SystemExit) as exc:
        cli._resolve_team(None)
    assert "no meta-teams found" in str(exc.value)


def test_resolve_team_missing_root_exits(tmp_path, monkeypatch):
    monkeypatch.setenv("META_TEAM_DIR", str(tmp_path / "does-not-exist"))
    with pytest.raises(SystemExit) as exc:
        cli._resolve_team(None)
    assert "no meta-teams found" in str(exc.value)


def test_resolve_team_multiple_lists_candidates(tmp_path, monkeypatch):
    _make_meta_root(tmp_path, monkeypatch, ["alpha", "beta", "gamma"])
    with pytest.raises(SystemExit) as exc:
        cli._resolve_team(None)
    msg = str(exc.value)
    assert "multiple meta-teams found" in msg
    for name in ("alpha", "beta", "gamma"):
        assert name in msg


def test_meta_team_dir_env_overrides_home(tmp_path, monkeypatch):
    # A team dir exists under META_TEAM_DIR but NOT under HOME/.claude/meta-teams.
    root = _make_meta_root(tmp_path, monkeypatch, ["env-team"])
    # Populate HOME default location with a different team to prove env wins.
    home_default = tmp_path / "home" / ".claude" / "meta-teams" / "home-team"
    home_default.mkdir(parents=True)
    assert cli._resolve_team(None) == "env-team"
    assert root.exists()


def _capture_run(monkeypatch):
    captured = {}

    def fake_run(argv, *a, **k):
        captured["argv"] = argv
        return type("R", (), {"returncode": 0})()

    monkeypatch.setattr(cli.subprocess, "run", fake_run)
    return captured


def test_send_builds_five_args_in_order(tmp_path, monkeypatch):
    _make_meta_root(tmp_path, monkeypatch, ["myteam"])
    captured = _capture_run(monkeypatch)
    args = cli.build_parser().parse_args(
        ["send", "teamA", "teamB", "hello world", "--team", "myteam"]
    )
    with pytest.raises(SystemExit) as exc:
        args.func(args)
    assert exc.value.code == 0
    argv = captured["argv"]
    assert argv[0] == "bash"
    assert argv[1].endswith(os.path.join("scripts", "send.sh"))
    # meta-team, from, to, type(default finding), message
    assert argv[2:] == ["myteam", "teamA", "teamB", "finding", "hello world"]


def test_send_type_flag_honored(tmp_path, monkeypatch):
    _make_meta_root(tmp_path, monkeypatch, ["myteam"])
    captured = _capture_run(monkeypatch)
    args = cli.build_parser().parse_args(
        ["send", "teamA", "all", "msg", "--type", "directive"]
    )
    with pytest.raises(SystemExit):
        args.func(args)
    assert captured["argv"][2:] == ["myteam", "teamA", "all", "directive", "msg"]


@pytest.mark.parametrize("cmd", [cli.cmd_status, cli.cmd_cleanup])
def test_status_and_cleanup_resolve_team(tmp_path, monkeypatch, cmd):
    _make_meta_root(tmp_path, monkeypatch, ["solo"])
    captured = _capture_run(monkeypatch)
    ns = type("A", (), {"team": None})()
    with pytest.raises(SystemExit):
        cmd(ns)
    assert captured["argv"][2] == "solo"


def test_cleanup_script_runs_clean(tmp_path, monkeypatch):
    """cleanup.sh with an empty findings dir and no running pids exits 0."""
    import subprocess

    root = tmp_path / "meta-teams"
    team_dir = root / "solo"
    (team_dir / "findings").mkdir(parents=True)
    (team_dir / "logs").mkdir()
    script = os.path.join(cli._scripts_dir(), "cleanup.sh")
    env = dict(os.environ, META_TEAM_DIR=str(root))
    proc = subprocess.run(
        ["bash", script, "solo"],
        env=env,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert not team_dir.exists()
