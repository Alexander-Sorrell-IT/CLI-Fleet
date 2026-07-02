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

## Multi-CLI fleets (v0.3.0)

Teams are no longer claude-only: each team in the config may set an optional
`"model"` (default `claude`). cli-fleet deploys the matching cli-enforcement
engine into that team's workdir, merges a mailbox-check hook into the model's
own hook file (without clobbering the enforcement hooks), and spawns the team
via that CLI's headless command.

```json
{
  "meta_team": "mixed-demo",
  "project_dir": "/path/to/project",
  "teams": [
    { "name": "team-claude",   "role": "backend",  "teammates": 2,
      "task": "Audit the API layer." },
    { "name": "team-gemini",   "role": "frontend", "teammates": 2,
      "task": "Audit the UI layer.",   "model": "gemini" },
    { "name": "team-deepseek", "role": "infra",    "teammates": 2,
      "task": "Audit the deploy scripts.", "model": "deepseek" }
  ]
}
```

| model | binary | headless spawn | mailbox hook event | launch-verified? |
|---|---|---|---|---|
| `claude` | `claude` | `claude --dangerously-skip-permissions -p <task>` | `UserPromptSubmit` | ✅ verified |
| `gemini` | `gemini` | `gemini --approval-mode yolo -p <task>` | `BeforeAgent` | ✅ verified |
| `deepseek` | `deepseek-code` | `deepseek-code --dangerously-skip-permissions -p <task>` | `UserPromptSubmit` | ✅ verified |
| `copilot` | `copilot` | `copilot --allow-all-tools --allow-all-paths -p <task>` | `UserPromptSubmit` | ✅ verified |
| `chatgpt` | `codex` | `codex exec --full-auto <task>` | `UserPromptSubmit` | ⚠ best-effort (from wiki docs; codex not verified locally — launch prints a warning) |
| `antigravity` | `agy` | `agy --dangerously-skip-permissions -p <task>` | `PreInvocation` | ✅ verified |

Shared state now lives at the model-neutral **`~/.cli-fleet/meta-teams/`**
(`META_TEAM_DIR` env still wins). If a legacy fleetcode `~/.claude/meta-teams`
exists, the new root is created as a symlink to it, so old fleets keep working.
The `dashboard` shows each team's model.

## License
MIT — see [LICENSE](LICENSE).
