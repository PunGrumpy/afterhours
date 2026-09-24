<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/afterhours-logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="./assets/afterhours-logo-light.svg">
  <img alt="Afterhours" src="./assets/afterhours-logo-light.svg" width="171" height="36">
</picture>

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat&colorA=000000&colorB=000000)
![Swift 6](https://img.shields.io/badge/Swift-6-000000?style=flat&colorA=000000&colorB=000000)

Your agents work after hours, this keeps your Mac awake for them.

Afterhours is a menu bar app that keeps your Mac awake while coding agents work, even with the lid closed. When the last agent finishes, it lets your Mac sleep again.

Works with Claude Code, Codex, OpenCode, Antigravity CLI, Gemini CLI, Copilot CLI, Cursor CLI, Aider, and Amp.

## Install

### 1. Build and run

You need macOS 14 or later and the Xcode Command Line Tools.

```bash
./scripts/build-app.sh --install
```

This builds a universal `Afterhours.app`, copies it to `/Applications`, and opens it. Leave off `--install` to build `build/Afterhours.app` only.

### 2. Keep it awake with the lid closed

macOS ignores keep-awake requests once you close the lid, so this step needs your admin password once. Open **Settings… > Power** and click **Install…** next to **Lid-closed mode**.

It adds `/etc/sudoers.d/afterhours`, which allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, nothing else.

### 3. Connect your agents

Open **Settings… > Agents** and click **Install** for each Claude Code config directory (`~/.claude`, `~/.claude-*`), then restart open Claude Code sessions.

Hooks tell Afterhours when Claude Code is working, waiting for you, or idle. Agents without hooks count as working while their processes use at least 3% of a CPU core, and for 45 seconds after that.

Any tool with hooks or plugins can report its own state:

```bash
afterhours-hook agent_id --state working --session session_id
```

`--state` accepts `working`, `waiting`, `idle`, or `end`.

### 4. Launch at login

Turn on **Settings… > General > Launch at login**. Press `⌥⌘L` anywhere to turn Afterhours on or off.

## Waiting for your reply

When agents finish or ask you something, Afterhours keeps your Mac awake so you can reply, and remote clients like T3 Code or SSH stay connected:

- **Plugged in:** it waits until every agent session closes
- **On battery:** it waits up to 1 hour after an agent last worked, so a forgotten session can't drain the battery

Change both in **Settings… > Power**.

## Reading the menu bar

The mug's steam shows the state at a glance:

- **Two wisps:** agents are working and your Mac stays awake
- **One wisp:** paused
- **No steam, eyes shut:** nothing is working, so your Mac can sleep
- **No steam, `> <` eyes:** a safety rule stopped Afterhours

## Safety

Afterhours lets your Mac sleep, even while agents work, when:

- Battery drops below the cutoff (15% by default)
- The Mac is on battery and **Only when plugged in** is on
- Low Power Mode is on and **Respect Low Power Mode** is on
- macOS reports a critical thermal state

If the lid is closed at that moment, Afterhours runs `pmset sleepnow`. On launch, it turns `disablesleep` off in case a previous run crashed while keeping the Mac awake.

Claude Code doesn't fire a `Stop` hook when you interrupt it with Esc, so a session that reports working with no CPU activity for 15 minutes counts as idle.

## Privacy

Afterhours runs on your Mac and makes no network requests. It reads process names and command lines to spot agents, and never reads your code or terminal output.

The hook receives each event Claude Code sends and keeps only these fields in `~/Library/Application Support/Afterhours/sessions/`:

- Session ID and agent name
- State: working, waiting, or idle
- Agent process ID and working directory
- Time of the last event

Afterhours deletes a session's file when its agent exits.

## Uninstall

Remove the system changes before deleting the app:

1. Click **Settings… > Power > Uninstall** to remove the sudoers rule.
2. Click **Settings… > Agents > Remove** for each config directory.
3. Delete the app and `~/Library/Application Support/Afterhours`.

Agent logos in `Resources/agents/` come from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT) and each vendor's own site. They're trademarks of their owners.
