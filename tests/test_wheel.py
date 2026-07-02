"""Build the wheel and assert the bundled scripts/ are inside it."""
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent


@pytest.mark.slow
def test_wheel_includes_scripts(tmp_path):
    out = tmp_path / "dist"
    subprocess.run(
        [sys.executable, "-m", "build", "--wheel", "--outdir", str(out), str(PROJECT_ROOT)],
        check=True,
        capture_output=True,
        text=True,
    )
    wheels = list(out.glob("*.whl"))
    assert len(wheels) == 1, wheels
    with zipfile.ZipFile(wheels[0]) as zf:
        names = zf.namelist()
    scripts = [n for n in names if n.startswith("cli_fleet/scripts/") and n.endswith(".sh")]
    assert any(n.endswith("scripts/send.sh") for n in scripts), scripts
    assert any(n.endswith("scripts/cleanup.sh") for n in scripts), scripts
    assert any(n.endswith("scripts/lib/protocol.sh") for n in scripts), scripts
