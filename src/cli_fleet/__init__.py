"""cli-fleet: launch multiple enforced Claude agent teams in parallel.

A thin Python wrapper around fleetcode's proven shell orchestration, adding
pip-install, hardware-aware capacity checks, and automatic enforcement (via
cli-enforcement, which itself uses cli-wikia). The shell scripts are bundled
verbatim — this layer adds the brains, not a rewrite.
"""

__version__ = "0.7.0"
