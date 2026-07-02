# CLI Fleet

Launch **multiple enforced Claude Code agent teams in parallel** — each team a
separate `claude` session in its own window, coordinating via a shared
filesystem mailbox. A thin, hardware-aware wrapper that completes the stack:

```
cli-wikia  →  cli-enforcement  →  cli-fleet
(knowledge)    (the brakes)        (the power)
```

`cli-fleet` bundles fleetcode's proven shell orchestration verbatim and adds:
- **Hardware gating** — refuses to launch more parallel agents than the box can take.
- **Automatic enforcement** — deploys the cli-enforcement engine into each team
  (hooks merged with fleetcode's mailbox hook), so every spawned team is governed.

## Install

```bash
pip install cli-fleet        # pulls in cli-enforcement + cli-wikia
```

## Usage

```bash
cli-fleet launch fleet.json            # hardware-gated, auto-enforced launch
cli-fleet launch fleet.json --background  # use `claude -p` instead of windows
cli-fleet status [meta-team]           # fleet status (auto-detects if one fleet)
cli-fleet dashboard [meta-team]        # scorecard: teams, mailbox, findings + per-team enforcement points
cli-fleet dashboard --watch 5          # redraw every 5s until Ctrl-C
cli-fleet send team-a team-b "message" --type finding   # cross-team mailbox message (--team to pick fleet)
cli-fleet cleanup [meta-team]          # tear down (auto-detects if one fleet)
```

Note: `cli-fleet launch` requires Linux with a terminal emulator (gnome-terminal/xterm family) unless `--background` is used.

## License
MIT — see [LICENSE](LICENSE).
