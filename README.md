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
cli-fleet status                       # fleet status
cli-fleet send team-a team-b "finding: ..."   # cross-team mailbox message
cli-fleet cleanup                      # tear down
```

## License
MIT — see [LICENSE](LICENSE).
