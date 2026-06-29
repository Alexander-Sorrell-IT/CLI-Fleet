"""cli-fleet command — wraps the bundled fleetcode scripts with hardware-aware
capacity checks and automatic enforcement."""
from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
from importlib import resources

from . import __version__


def _scripts_dir():
    return str(resources.files("cli_fleet") / "scripts")


def _run_script(name, args):
    path = os.path.join(_scripts_dir(), name)
    if not os.path.exists(path):
        sys.exit(f"bundled script missing: {name}")
    st = os.stat(path)
    os.chmod(path, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    return subprocess.run(["bash", path, *args]).returncode


def _hardware_gate(config_path, force):
    """Use cli-enforcement's detector to refuse over-capacity launches."""
    try:
        from cli_enforcement import fleet as F
    except ImportError:
        print("ℹ cli-enforcement not installed — skipping hardware/enforcement.")
        return True, None
    try:
        with open(config_path, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        sys.exit(f"bad config: {e}")
    hw = F.detect_hardware()
    want = F.requested_agents(cfg)
    cap = hw["max_parallel_agents"]
    print(f"hardware:  {hw['cpu_cores']} cores, {hw['ram_gb']} GB -> safe max ~{cap} agents")
    print(f"requested: {len(cfg.get('teams', []))} teams, {want} agents")
    if want > cap and not force:
        print(f"⚠ OVER CAPACITY by {want - cap}.")
        sys.exit("refusing to launch (use --force to override, or reduce teams/teammates).")
    if want > cap:
        print(f"⚠ over capacity by {want - cap} — launching anyway (--force).")
    return True, cfg


def cmd_launch(args):
    _hardware_gate(args.config, args.force)
    if not args.no_enforce:
        # Bake hardware + enforcement sections into the config first.
        _run_enforce_fleet(args.config)
    extra = ["--background"] if args.background else []
    print("launching fleet…")
    rc = _run_script("launch.sh", [os.path.abspath(args.config), *extra])
    sys.exit(rc)


def _run_enforce_fleet(config_path):
    try:
        from cli_enforcement import fleet as F
    except ImportError:
        return
    ns = type("A", (), {"config": config_path, "per_team_points": False, "write": True})()
    try:
        F.cmd_fleet(ns)
    except SystemExit:
        pass


def cmd_status(args):
    sys.exit(_run_script("status.sh", []))


def cmd_send(args):
    sys.exit(_run_script("send.sh", [args.frm, args.to, args.message]))


def cmd_cleanup(args):
    sys.exit(_run_script("cleanup.sh", []))


def cmd_where(args):
    print(_scripts_dir())


def build_parser():
    p = argparse.ArgumentParser(
        prog="cli-fleet",
        description="Launch multiple enforced Claude agent teams in parallel "
        "(hardware-aware wrapper over fleetcode + cli-enforcement + cli-wikia).",
    )
    p.add_argument("--version", action="version", version=f"cli-fleet {__version__}")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("launch", help="launch a fleet from a config (hardware-gated, auto-enforced)")
    s.add_argument("config", help="fleetcode config.json")
    s.add_argument("--background", action="store_true", help="use `claude -p` instead of terminal windows")
    s.add_argument("--force", action="store_true", help="launch even if over hardware capacity")
    s.add_argument("--no-enforce", action="store_true", help="skip enforcement deployment")
    s.set_defaults(func=cmd_launch)

    s = sub.add_parser("status", help="show fleet status")
    s.set_defaults(func=cmd_status)

    s = sub.add_parser("send", help="send a cross-team mailbox message")
    s.add_argument("frm")
    s.add_argument("to")
    s.add_argument("message")
    s.set_defaults(func=cmd_send)

    s = sub.add_parser("cleanup", help="tear down a fleet")
    s.set_defaults(func=cmd_cleanup)

    s = sub.add_parser("where", help="print the bundled scripts directory")
    s.set_defaults(func=cmd_where)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
