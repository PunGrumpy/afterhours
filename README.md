# Afterhours

Afterhours is a macOS menu bar app that keeps your Mac awake while coding agents work, even with the lid closed, and lets it sleep again when they finish.

## How Afterhours keeps your Mac awake

Afterhours combines two macOS mechanisms with two ways of detecting agent activity:

| Piece | Role |
| --- | --- |
| `PreventUserIdleSystemSleep` assertion | Keeps the Mac awake while the lid is open. |
| `pmset -a disablesleep 1` | Keeps the Mac awake with the lid closed. This command needs root, so installing lid-closed mode adds `/etc/sudoers.d/afterhours`, which allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. |
| `afterhours-hook` | Claude Code hooks run this binary, which records each session as working, waiting for you, or idle in `~/Library/Application Support/Afterhours/sessions/`. |
| Process detection | Agents without hooks (Codex, OpenCode, Gemini CLI, Copilot CLI, Cursor Agent, Aider, Amp) count as working while their processes use at least 3% of a CPU core, and for 45 seconds after that. |

Afterhours stops keeping your Mac awake when any of these safety rules applies:

- Battery drops below the cutoff (15% by default)
- The Mac is on battery and **Only when plugged in** is on
- Low Power Mode is on and **Respect Low Power Mode** is on
- macOS reports a critical thermal state

If the lid is closed when Afterhours stops keeping the Mac awake, it runs `pmset sleepnow`. On launch, it turns `disablesleep` off in case a previous run crashed while keeping the Mac awake.

Claude Code doesn't fire a `Stop` hook when you interrupt it with Esc. To cover that case, Afterhours treats a session as idle after it reports working for 15 minutes with no CPU activity.

## Build the app

You need macOS 14 or later and the Xcode Command Line Tools. Run the build script:

```sh
./scripts/build-app.sh            # builds build/Afterhours.app (universal)
./scripts/build-app.sh --install  # also copies it to /Applications and launches it
```

The script calls `swiftc` directly and picks the newest SDK your compiler accepts, so it works when SwiftPM in the Command Line Tools is broken. Use `Package.swift` to open the project in Xcode.

## Set up lid-closed mode and agent hooks

Complete these steps once after installing:

1. Open **Settings… > Power** and click **Install…** next to **Lid-closed mode**. macOS asks for your admin password once.
2. Open **Settings… > Agents** and click **Install** for each Claude Code config directory (`~/.claude`, `~/.claude-*`). Afterhours backs up the original file to `settings.json.afterhours-backup`.
3. Restart open Claude Code sessions so they load the hooks.
4. Optional: turn on **Settings… > General > Launch at login**.

Press `⌥⌘L` anywhere to turn Afterhours on or off.

### Report status from other agents

Any tool with hook or plugin support can report an exact state by calling `afterhours-hook`:

```sh
afterhours-hook agent_id --state working --session session_id
```

`--state` accepts `working`, `waiting`, `idle`, or `end`.

## Uninstall Afterhours

Remove the system changes before deleting the app:

1. Click **Settings… > Power > Uninstall** to remove the sudoers rule.
2. Click **Settings… > Agents > Remove** for each config directory.
3. Delete the app and `~/Library/Application Support/Afterhours`.

## Mascot and logos

The mascot is a coffee mug, the fuel of after-hours work. Its steam shows the state at a glance: two wisps while Afterhours keeps your Mac awake, one while paused, and none when your Mac can sleep. Its face backs that up, with `> <` eyes when a safety rule stops it. `Sources/Afterhours/Mascot.swift` draws it as vector shapes, with slightly larger eyes at menu bar size so it stays readable at 16 pt.

The logos in `Resources/agents/` come from each vendor's website or VS Code Marketplace listing. They're trademarks of their owners, so keep this build for personal use.
