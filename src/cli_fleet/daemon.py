"""cli-fleet daemon — monitor a meta-team fleet headlessly in the background.

Commands:
  cli-fleet daemon start [--team TEAM]   # daemonize and watch the fleet
  cli-fleet daemon stop                  # stop the daemon
  cli-fleet daemon status                # show running state + last event
  cli-fleet daemon logs [-n N]           # tail the daemon log

The daemon polls the meta-team registry, mailbox, and findings every 5s and
logs state changes: new messages, dead teams, new findings, team completions.
Same data as `cli-fleet dashboard --watch` but runs headlessly.
"""
from __future__ import annotations

import json
import os
import signal
import sys
import time

from . import __version__
from .cli import _meta_dir, _load_json


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

def _state_dir() -> str:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return os.path.join(base, "cli-fleet")


def _pid_path() -> str:
    return os.path.join(_state_dir(), "daemon.pid")


def _log_path() -> str:
    return os.path.join(_state_dir(), "daemon.log")


# ---------------------------------------------------------------------------
# PID helpers
# ---------------------------------------------------------------------------

def _read_pid() -> int | None:
    try:
        return int(open(_pid_path()).read().strip())
    except (OSError, ValueError):
        return None


def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _write_pid(pid: int) -> None:
    os.makedirs(_state_dir(), exist_ok=True)
    with open(_pid_path(), "w") as f:
        f.write(str(pid))


def _clear_pid() -> None:
    try:
        os.remove(_pid_path())
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Daemonize
# ---------------------------------------------------------------------------

def _daemonize(log_path: str) -> None:
    if os.fork() > 0:
        sys.exit(0)
    os.setsid()
    if os.fork() > 0:
        sys.exit(0)
    devnull = open(os.devnull, "r")
    os.dup2(devnull.fileno(), sys.stdin.fileno())
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    logfile = open(log_path, "a", buffering=1)
    os.dup2(logfile.fileno(), sys.stdout.fileno())
    os.dup2(logfile.fileno(), sys.stderr.fileno())


def _log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Fleet state helpers
# ---------------------------------------------------------------------------

def _team_alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def _mailbox_count(dir_: str) -> int:
    try:
        return len([f for f in os.listdir(os.path.join(dir_, "mailbox")) if f.endswith(".json")])
    except OSError:
        return 0


def _findings_count(dir_: str) -> int:
    try:
        return len([f for f in os.listdir(os.path.join(dir_, "findings")) if f.endswith(".json")])
    except OSError:
        return 0


def _snapshot(team_dir: str) -> dict:
    registry = _load_json(os.path.join(team_dir, "registry.json"), {})
    teams = {
        t["name"]: _team_alive(t.get("pid"))
        for t in registry.get("teams", [])
        if t.get("name")
    }
    return {
        "teams": teams,
        "mailbox": _mailbox_count(team_dir),
        "findings": _findings_count(team_dir),
    }


# ---------------------------------------------------------------------------
# Main daemon loop
# ---------------------------------------------------------------------------

def _daemon_loop(team: str, poll_interval: float = 5.0) -> None:
    team_dir = os.path.join(_meta_dir(), team)
    _log(f"cli-fleet daemon v{__version__} watching team: {team}  ({team_dir})")
    _write_pid(os.getpid())

    def _handle_term(sig, frame):
        _log("daemon stopping (SIGTERM).")
        _clear_pid()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _handle_term)
    signal.signal(signal.SIGINT, _handle_term)

    prev: dict = {}

    while True:
        if not os.path.isdir(team_dir):
            time.sleep(poll_interval)
            continue

        cur = _snapshot(team_dir)

        if prev:
            # New mailbox messages
            new_msgs = cur["mailbox"] - prev.get("mailbox", 0)
            if new_msgs > 0:
                _log(f"mailbox: +{new_msgs} message(s)  (total {cur['mailbox']})")

            # New findings
            new_findings = cur["findings"] - prev.get("findings", 0)
            if new_findings > 0:
                _log(f"findings: +{new_findings} new  (total {cur['findings']})")

            # Team alive/dead transitions
            prev_teams = prev.get("teams", {})
            for name, alive in cur["teams"].items():
                was_alive = prev_teams.get(name)
                if was_alive and not alive:
                    _log(f"team DIED: {name}")
                elif was_alive is False and alive:
                    _log(f"team RESTARTED: {name}")

            # New teams registered
            for name in cur["teams"]:
                if name not in prev_teams:
                    alive = cur["teams"][name]
                    _log(f"team REGISTERED: {name}  (alive={alive})")
        else:
            # First snapshot — log initial state
            n_alive = sum(1 for a in cur["teams"].values() if a)
            n_total = len(cur["teams"])
            _log(f"initial: {n_alive}/{n_total} teams alive  mailbox={cur['mailbox']}  findings={cur['findings']}")

        prev = cur
        time.sleep(poll_interval)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_start(args):
    from .cli import _resolve_team
    team = _resolve_team(getattr(args, "team", None))
    pid = _read_pid()
    if pid and _is_alive(pid):
        print(f"cli-fleet daemon already running (pid {pid}).")
        return

    log = _log_path()
    if not getattr(args, "foreground", False):
        _daemonize(log)
        _daemon_loop(team)
    else:
        print(f"cli-fleet daemon starting (foreground) — watching team: {team}")
        print(f"log: {log}  (Ctrl-C to stop)")
        _write_pid(os.getpid())
        try:
            _daemon_loop(team)
        except KeyboardInterrupt:
            _clear_pid()
            print("\ndaemon stopped.")


def cmd_stop(args):
    pid = _read_pid()
    if not pid:
        print("cli-fleet daemon is not running.")
        return
    if not _is_alive(pid):
        print(f"stale pid {pid} — clearing.")
        _clear_pid()
        return
    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        time.sleep(0.1)
        if not _is_alive(pid):
            break
    _clear_pid()
    print(f"cli-fleet daemon (pid {pid}) stopped.")


def cmd_status(args):
    pid = _read_pid()
    log = _log_path()
    if pid and _is_alive(pid):
        print(f"cli-fleet daemon: RUNNING  (pid {pid})")
    elif pid:
        print(f"cli-fleet daemon: DEAD  (stale pid {pid})")
    else:
        print("cli-fleet daemon: STOPPED")
    print(f"log: {log}" + ("" if os.path.exists(log) else "  (no log yet)"))
    if os.path.exists(log):
        lines = open(log).readlines()
        last = next((l.rstrip() for l in reversed(lines) if l.strip()), None)
        if last:
            print(f"last: {last.strip()}")


def cmd_logs(args):
    log = _log_path()
    if not os.path.exists(log):
        print(f"no log file yet: {log}")
        return
    lines = open(log).readlines()
    n = getattr(args, "lines", 40)
    for line in lines[-n:]:
        print(line, end="")
