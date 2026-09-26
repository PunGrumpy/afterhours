# @afterhours/macos

## 0.2.1

### Patch Changes

- 379bc9d: A stuck Claude Code session now times out after 15 minutes even when Afterhours can't match its process to a running agent, and an agent no longer shows up twice when its hook reports a child process. CPU activity is no longer sampled from scans less than a second apart, so a screen redraw can't be mistaken for real work.
- 7a897d1: A Mac docked to an external display with its lid closed now stays awake when agents finish, when you pause, and when you turn Afterhours off. Afterhours only puts a closed Mac to sleep when closing the lid would sleep it anyway. Stopping Afterhours with `kill` or `pkill` now turns lid-closed mode off before the app exits. A laptop whose battery can't be read no longer counts as plugged in.
- 807fab5: Lid-closed mode now writes its sudoers rule from the privileged step itself, so nothing else running as your user can change the rule while the password prompt is open.

## 0.2.0

### Minor Changes

- 8607727: Show subscription limits in the menu for Claude Code, Codex, Cursor, Copilot, OpenCode Go, and Grok Build. Each window is a bar of what's left, colored by where the current burn rate lands, with its reset countdown, read with the logins the tools already keep. Accounts pooled on a CLIProxyAPI hub join too, once you add the hub under **Settings… > Limits > Usage providers**. Turn it all off in **Settings… > Limits**.
- 8607727: Settings now has General, Power, Agents, and Limits tabs, and the window fits the tab you're on instead of scrolling. Process detection is a two-column list of checkboxes, and the display option moved to General.

## 0.1.0

The first release of Afterhours, a menu bar app that keeps your Mac awake while coding agents work.

### Features

- Keeps your Mac awake while Claude Code, Codex, OpenCode, Antigravity CLI, Gemini CLI, Copilot CLI, Cursor CLI, Aider, Amp, Droid, Goose, Kiro CLI, Kilo CLI, OpenClaw, Hermes Agent, or Cline CLI works, and lets it sleep when the last one finishes.
- Keeps a closed Mac awake on AC power with no setup. On battery, lid-closed mode adds a sudoers rule that allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`.
- Claude Code hooks report when a session is working, waiting for you, or idle. Other agents count as working while their processes use at least 3% of a CPU core.
- Waits for your reply after agents finish, so remote clients like T3 Code and SSH stay connected: until every session closes when plugged in, and up to 1 hour on battery.
- Lets your Mac sleep below a battery cutoff, on battery when **Only when plugged in** is on, in Low Power Mode, or at a critical thermal state, and warns you 5% before the cutoff.
- The menu bar mug shows the state with its steam. Press `⌥⌘L` to turn Afterhours on or off.
- The menu follows Increase Contrast, Reduce Transparency, and Reduce Motion.
