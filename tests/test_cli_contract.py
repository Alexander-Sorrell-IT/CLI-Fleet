"""Every advertised command must actually run.

`--help` is the one path a user hits before anything else, and it is the only
path that exercises argparse wiring for the entire command tree without side
effects. A subcommand that was renamed in code but left in help, a subparser
whose defaults raise at construction, an entry point that no longer imports —
all of them surface here and nowhere else in the suite.

The tree is walked rather than enumerated, so a command added tomorrow is
covered without touching this file, and a command deleted tomorrow stops being
asserted automatically.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

MODULE = "cli_fleet"
SRC = str(Path(__file__).resolve().parents[1] / "src")
MAX_DEPTH = 3
TIMEOUT = 30


def _run(args):
    """Invoke the CLI in a real process, the way a user does."""
    env = dict(os.environ)
    env["PYTHONPATH"] = SRC + os.pathsep + env.get("PYTHONPATH", "")
    env["COLUMNS"] = "80"          # stable wrapping across terminals
    env.pop("CLAUDE_CONFIG_DIR", None)   # never read the developer's real config
    env.pop("WIKIA_CONFIG_DIR", None)
    code = f"import sys; sys.argv={[MODULE] + list(args)!r}; from {MODULE}.cli import main; main()"
    return subprocess.run([sys.executable, "-c", code], capture_output=True,
                          text=True, timeout=TIMEOUT, env=env)


def _subcommands(help_text):
    """Pull subcommand names out of argparse's `{a,b,c}` metavar."""
    out = []
    for m in re.finditer(r"\{([a-z0-9][a-z0-9,_-]*)\}", help_text):
        out.extend(p for p in m.group(1).split(",") if p)
    seen, uniq = set(), []
    for c in out:
        if c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


def _walk(prefix=(), depth=0):
    """Yield every command path in the tree, breadth first."""
    if depth > MAX_DEPTH:
        return
    r = _run(list(prefix) + ["--help"])
    if r.returncode != 0:
        return
    for sub in _subcommands(r.stdout):
        path = prefix + (sub,)
        yield path
        yield from _walk(path, depth + 1)


def _all_paths():
    try:
        return [()] + list(_walk())
    except Exception:
        return [()]


PATHS = _all_paths()


def test_entry_point_imports():
    """The console script's target must import — a broken import makes every
    other assertion here vacuous, so it is checked on its own."""
    r = subprocess.run(
        [sys.executable, "-c", f"import sys; sys.path.insert(0, {SRC!r}); from {MODULE}.cli import main"],
        capture_output=True, text=True, timeout=TIMEOUT)
    assert r.returncode == 0, r.stderr


def test_top_level_help_works():
    r = _run(["--help"])
    assert r.returncode == 0, f"`--help` exited {r.returncode}\n{r.stderr}"
    assert r.stdout.strip(), "`--help` printed nothing"


def test_the_tree_was_actually_discovered():
    """Guards the guard. If subcommand parsing silently returns nothing, every
    parametrised case below collapses to one trivial check and the suite looks
    green while testing almost nothing."""
    assert len(PATHS) > 1, f"discovered no subcommands — parsing is broken, not the CLI ({PATHS})"


@pytest.mark.parametrize("path", PATHS, ids=lambda p: " ".join(p) or "<root>")
def test_help_works_for_every_command(path):
    r = _run(list(path) + ["--help"])
    cmd = " ".join((MODULE,) + tuple(path))
    assert r.returncode == 0, f"`{cmd} --help` exited {r.returncode}\n{r.stderr[-800:]}"
    assert r.stdout.strip(), f"`{cmd} --help` printed nothing"


def test_unknown_command_fails_loudly():
    """An unknown command must be an error, not a silent no-op that leaves the
    user believing something ran."""
    r = _run(["definitely-not-a-real-command"])
    assert r.returncode != 0, "unknown command exited 0"
