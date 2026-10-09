# @afterhours/macos

## 0.2.5

### Patch Changes

- 3dfeb26: Afterhours now has its own icon, the coffee mug on a navy tile, so you can spot it in Finder, Launchpad, Spotlight, and the Applications folder instead of a blank app.

## 0.2.4

### Patch Changes

- d4a2d19: Turning on detection for an agent that's already running no longer counts the CPU it used earlier as new work, so it doesn't start a hold and keep your Mac awake for nothing.
- 9ec8334: You can turn off the ⌥⌘L shortcut in Settings > General, so it stops taking those keys from other apps, like Reformat Code in JetBrains IDEs or Downloads in Finder and Safari. Pressing ⌥⌘L now always tells you whether it turned Afterhours on or off, and Settings tells you when another app already uses the shortcut.
- bc1815a: Afterhours now sends a hub's management key only over https, or over http to a hub on this Mac or your local network. A hub saved with any other http address shows "Use https for a hub that isn't on this Mac or your local network" instead of sending the key unencrypted.
- 31b6ea9: Removing or reinstalling the Claude Code hooks no longer deletes your own hook commands when they sit in the same group as Afterhours's. Afterhours now takes out only its own commands.
- 6772647: Afterhours now checks your subscription limits in the background only while agents work, as its privacy policy says, instead of every 5 minutes for as long as it waits for your reply. Opening the menu still refreshes them.
- fcb8e1f: Afterhours now cleans up before it exits when the terminal that started it closes, the same way it already did for `kill` and `pkill`, so lid-closed mode doesn't stay on. An error about installing the hook at launch also stays in the menu instead of disappearing the next time a hold starts or ends.
- bb8977f: If Afterhours crashes or you Force Quit it while it keeps a closed Mac awake on battery, a small helper now turns `pmset disablesleep` back off right away, so your Mac can sleep again instead of staying awake until Afterhours opens. During a hold, Afterhours also turns it back on if something else turned it off.
- 9752e36: Limits now reads your Cursor login even when your `sqliterc` turns on headers or another output mode. Monthly bars measure the burn rate against the real length of the month, so they show the right color early in February and in 31-day months. Two accounts that haven't been used yet no longer merge into one row. A garbled reset time from a provider or hub can no longer crash Afterhours.

## 0.2.3

### Patch Changes

- 9dfd42f: Limits opens and closes faster, in 0.25 seconds instead of 0.35, and usage bars reach their new length just as quickly.
- a296f46: You can hide the Afterhours icon with Settings > General > Show in menu bar. Afterhours keeps your Mac awake while the icon is hidden, and opening it again from Applications or Spotlight brings back Settings.
- a296f46: Opening Afterhours again from Applications or Spotlight while it runs now shows Settings, so you can reach it when a crowded menu bar hides the icon.

## 0.2.2

### Patch Changes

- ce7587b: The Limits section now names your Codex plan the way Codex does. "Prolite" becomes "Pro", the plan that showed as "Pro" becomes "Pro (More)", and "Edu_plus" becomes "Edu Plus".
- 41ab3f7: Afterhours now detects Grok Build, Qwen Code, Crush, Pi, and fx, so your Mac stays awake while they work. It only counts the fx that fx.sh installs in `~/.local/bin`, so leaving the fx JSON viewer open won't keep your Mac awake.

## 0.2.1

### Patch Changes

- 379bc9d: A stuck Claude Code session now times out after 15 minutes even when Afterhours can't match its process to a running agent, and an agent no longer shows up twice when its hook reports a child process. CPU activity is no longer sampled from scans less than a second apart, so a screen redraw can't be mistaken for real work.
- ebb5f1b: Installing or removing Claude Code hooks no longer overwrites your `settings.json` when it isn't valid JSON. You'll see an error instead, and your file stays untouched. Afterhours now keeps a fresh `settings.json.afterhours-backup` before every write, and writes through a symlinked `settings.json` instead of replacing it. The hook CLI ignores an unrecognized `--state` value instead of treating it as working, and the menu shows an error if the hook binary fails to install at launch.
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
