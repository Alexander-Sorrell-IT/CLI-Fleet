"""Hermetic tests for `cli-fleet dashboard` — fake meta-team dir, no real ~/.claude."""
import json
import os

from cli_fleet import cli


def _make_fake_team(tmp_path, monkeypatch, name="demo", workdir=None):
    root = tmp_path / "meta-teams"
    dir_ = root / name
    for sub in ("mailbox", "findings", "tasks", "status"):
        (dir_ / sub).mkdir(parents=True)
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))

    registry = {
        "meta_team": name,
        "teams": [
            {"name": "backend", "role": "api", "pid": os.getpid(),
             "workdir": workdir or str(tmp_path / "nowhere"), "status": "active"},
            {"name": "frontend", "role": "ui", "pid": 999999999,
             "workdir": "", "status": "active"},
        ],
    }
    (dir_ / "registry.json").write_text(json.dumps(registry))

    for i, mtype in enumerate(["finding", "finding", "task", "status"]):
        msg = {"id": str(i), "from": "backend", "to": "all", "type": mtype, "content": "x"}
        (dir_ / "mailbox" / f"{i}-backend-to-all.json").write_text(json.dumps(msg))

    (dir_ / "findings" / "backend-F1.json").write_text(
        json.dumps({"id": "F1", "team": "backend", "severity": "high", "title": "t"})
    )
    (dir_ / "tasks.json").write_text(
        json.dumps({"tasks": [{"id": "T1", "status": "pending"},
                              {"id": "T2", "status": "completed"}]})
    )
    return dir_


def test_dashboard_counts_correct(tmp_path, monkeypatch):
    _make_fake_team(tmp_path, monkeypatch)
    data = cli.gather_dashboard("demo")
    assert data["meta_team"] == "demo"
    assert data["mailbox"]["total"] == 4
    assert data["mailbox"]["by_type"] == {"finding": 2, "task": 1, "status": 1}
    assert data["findings"] == 1
    assert data["tasks"] == {"pending": 1, "completed": 1}
    names = {t["name"]: t for t in data["teams"]}
    assert set(names) == {"backend", "frontend"}
    assert names["backend"]["alive"] is True  # our own pid
    assert names["frontend"]["alive"] is False


def test_dashboard_enforcement_na_when_unavailable(tmp_path, monkeypatch):
    """Workdirs without a deployed engine render as n/a, never traceback."""
    _make_fake_team(tmp_path, monkeypatch)
    data = cli.gather_dashboard("demo")
    assert all(t["enforcement"] is None for t in data["teams"])
    out = cli.render_dashboard(data)
    assert "enforcement: n/a" in out
    assert "4 messages" in out
    assert "findings: 1" in out


def test_dashboard_shows_enforcement_points(tmp_path, monkeypatch):
    workdir = tmp_path / "proj"
    workdir.mkdir()
    _make_fake_team(tmp_path, monkeypatch, workdir=str(workdir))

    fake = {"points": {"current": 640, "tier": 2, "tier_name": "Standard"},
            "failure": {"hard_stop": False}}

    def fake_run(argv, *a, **k):
        assert argv[:3] == ["cli-enforcement", "status", "--json"]
        return type("R", (), {"returncode": 0, "stdout": json.dumps(fake)})()

    monkeypatch.setattr(cli.subprocess, "run", fake_run)
    data = cli.gather_dashboard("demo")
    backend = next(t for t in data["teams"] if t["name"] == "backend")
    assert backend["enforcement"] == {
        "points": 640, "tier": 2, "tier_name": "Standard", "hard_stop": False,
    }
    assert "pts=640 T2:Standard" in cli.render_dashboard(data)


def test_dashboard_missing_meta_files_degrade(tmp_path, monkeypatch):
    root = tmp_path / "meta-teams"
    (root / "bare").mkdir(parents=True)  # no registry/mailbox/etc at all
    monkeypatch.setenv("META_TEAM_DIR", str(root))
    data = cli.gather_dashboard("bare")
    assert data["teams"] == []
    assert data["mailbox"]["total"] == 0
    assert data["findings"] == 0
    assert "(none registered)" in cli.render_dashboard(data)
