# CLI Fleet - Multi-CLI Agent Orchestration

## Overview

**CLI Fleet** is a hardware-aware orchestration layer that launches **multiple enforced AI agent teams in parallel**. Each team runs as a separate CLI session (Claude, Gemini, DeepSeek, Copilot, ChatGPT/Codex, Antigravity, or Grok) in its own window or background process, coordinating via a shared filesystem mailbox.

This tool completes the CLI agent stack:

```
cli-wikia      →  cli-enforcement  →  cli-fleet
(knowledge)       (the brakes)         (the power)
```

### Key Features

- **Multi-CLI Support**: Not just for Claude! Launch teams using any supported AI CLI tool
- **Hardware Gating**: Automatically refuses to launch more parallel agents than your system can handle
- **Automatic Enforcement**: Deploys the cli-enforcement engine into each team, ensuring every spawned team is governed
- **Shared Mailbox**: Teams coordinate via a filesystem-based mailbox system
- **Dashboard & Monitoring**: Real-time status, scorecards, and cross-team messaging

## Installation

```bash
pip install cli-fleet
```

This pulls in `cli-enforcement` and `cli-wikia` as dependencies.

## Quick Start

### 1. Create a Fleet Configuration

Create a JSON file defining your teams:

```json
{
  "meta_team": "my-project",
  "project_dir": "/path/to/your/project",
  "teams": [
    {
      "name": "team-backend",
      "role": "backend",
      "teammates": 2,
      "task": "Audit the API layer and identify security vulnerabilities."
    },
    {
      "name": "team-frontend",
      "role": "frontend",
      "teammates": 2,
      "task": "Review the UI components for accessibility issues.",
      "model": "gemini"
    },
    {
      "name": "team-infra",
      "role": "infrastructure",
      "teammates": 2,
      "task": "Audit deployment scripts and CI/CD pipelines.",
      "model": "deepseek"
    }
  ]
}
```

### 2. Launch Your Fleet

```bash
# Standard launch (opens terminal windows)
cli-fleet launch fleet.json

# Background mode (no windows, uses headless CLI flags)
cli-fleet launch fleet.json --background

# Check status
cli-fleet status my-project

# View dashboard with enforcement metrics
cli-fleet dashboard my-project

# Watch dashboard (refreshes every 5 seconds)
cli-fleet dashboard --watch 5

# Send cross-team messages
cli-fleet send team-backend team-frontend "Found API issue in /api/users" --type finding

# Cleanup when done
cli-fleet cleanup my-project
```

## Supported CLI Tools

| Model | Binary | Headless Spawn | Mailbox Hook Event | Verified |
|-------|--------|----------------|-------------------|----------|
| `claude` | `claude` | `claude --dangerously-skip-permissions -p <task>` | `UserPromptSubmit` | ✅ |
| `gemini` | `gemini` | `gemini --approval-mode yolo -p <task>` | `BeforeAgent` | ✅ |
| `deepseek` | `deepseek-code` | `deepseek-code --dangerously-skip-permissions -p <task>` | `UserPromptSubmit` | ✅ |
| `copilot` | `copilot` | `copilot --allow-all-tools --allow-all-paths -p <task>` | `UserPromptSubmit` | ✅ |
| `chatgpt` | `codex` | `codex exec --full-auto <task>` | `UserPromptSubmit` | ⚠️ Best-effort |
| `antigravity` | `agy` | `agy --dangerously-skip-permissions -p <task>` | `PreInvocation` | ✅ |
| `grok` | `grok` | `grok -p <task>` | N/A | ✅ |

**Note**: The `model` field in team configuration is optional and defaults to `claude`.

## Architecture

### Meta-Team Directory

Shared state lives at `~/.cli-fleet/meta-teams/` (or `$META_TEAM_DIR` if set). If a legacy fleetcode `~/.claude/meta-teams` exists, it's automatically symlinked for backward compatibility.

Directory structure:
```
~/.cli-fleet/meta-teams/
└── <meta-team-name>/
    ├── teams/
    │   ├── team-backend/
    │   │   ├── workdir/
    │   │   └── .claude/settings.json (with enforcement hooks)
    │   ├── team-frontend/
    │   └── team-infra/
    └── mailbox/
        └── ... (shared message files)
```

### Enforcement Integration

When a team is launched:
1. cli-fleet deploys the matching cli-enforcement engine into the team's workdir
2. A mailbox-check hook is merged into the model's hook file (without clobbering enforcement hooks)
3. The team is spawned via the model's configured headless or interactive command

### Hardware Gating

The launcher checks system resources before launching teams and will refuse to start if:
- CPU core count would be exceeded
- Memory constraints would be violated
- Too many parallel sessions would degrade performance

## CLI Commands

### `cli-fleet launch <config.json>`

Launch all teams defined in the configuration file.

**Options:**
- `--background`: Use headless mode (`-p` flag) instead of opening terminal windows
- `--dry-run`: Show what would be launched without actually starting teams

### `cli-fleet status [meta-team]`

Display the current status of teams in a fleet. Auto-detects meta-team if only one exists.

### `cli-fleet dashboard [meta-team]`

Show a scorecard with:
- Team count and status
- Mailbox activity
- Findings summary
- Per-team enforcement points

**Options:**
- `--watch <seconds>`: Redraw every N seconds until Ctrl-C

### `cli-fleet send <from-team> <to-team> "<message>"`

Send a cross-team mailbox message.

**Options:**
- `--type <type>`: Message type (e.g., `finding`, `question`, `update`)
- `--team <fleet>`: Specify which fleet if multiple exist

### `cli-fleet cleanup [meta-team]`

Tear down a fleet and clean up temporary files. Auto-detects meta-team if only one exists.

## Extending the Registry

### Adding a New CLI Model

To add support for a new CLI tool:

1. Edit `src/cli_fleet/models.json` and add an entry:

```json
{
  "models": {
    "your-model": {
      "binary": "your-cli-binary",
      "headless": ["your-cli-binary", "--skip-permissions", "-p", "{prompt}"],
      "interactive": ["your-cli-binary", "--skip-permissions", "{prompt}"],
      "mailbox_event": "UserPromptSubmit",
      "enforce": true,
      "verified": false
    }
  }
}
```

2. Ensure `cli-enforcement` has corresponding hook file specs for your model
3. Test with `--dry-run` first, then verify manually

### Using cli-collective Overrides

When `cli-collective` is installed, its `models.json` acts as an override layer. Add a `"fleet"` section to override any field from one central location.

## Requirements

- **Linux** with a terminal emulator (gnome-terminal, xterm, etc.) for windowed mode
- **Python 3.8+**
- Supported CLI tools installed and configured (claude, gemini, deepseek-code, copilot, codex, agy, grok)

## Troubleshooting

### Terminal Emulator Not Found

If `cli-fleet launch` fails to open windows:
- Install a supported terminal emulator: `sudo apt install gnome-terminal` or `xterm`
- Or use `--background` mode for headless operation

### Model Not Recognized

- Check that the CLI binary is in your PATH
- Verify the model name matches exactly (case-sensitive)
- Run `cli-fleet launch --dry-run` to see resolved commands

### Enforcement Hooks Not Working

- Ensure `cli-enforcement` is installed
- Check that the model has `enforce: true` in models.json
- Verify the hook file was created in the team's `.claude/settings.json`

## License

[PolyForm Noncommercial 1.0.0](LICENSE) — free for noncommercial use.

Commercial use requires a paid license: matrixbuilderops@proton.me

## Related Projects

- **[cli-wikia](https://github.com/fleetcode/cli-wikia)**: Knowledge base for CLI configurations
- **[cli-enforcement](https://github.com/fleetcode/cli-enforcement)**: Governance and safety hooks for AI agents
- **[cli-collective](https://github.com/fleetcode/cli-collective)**: Centralized configuration overrides
