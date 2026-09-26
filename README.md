<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./assets/afterhours-logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="./assets/afterhours-logo-light.svg">
  <img alt="Afterhours" src="./assets/afterhours-logo-light.svg" width="171" height="36">
</picture>

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat&colorA=000000&colorB=000000) ![Swift 6](https://img.shields.io/badge/Swift-6-000000?style=flat&colorA=000000&colorB=000000)

Your agents work after hours, this keeps your Mac awake for them.

Afterhours is a menu bar app that keeps your Mac awake while coding agents work, even with the lid closed. When the last agent finishes, it lets your Mac sleep again.

Works with Claude Code, Codex, OpenCode, Antigravity CLI, Gemini CLI, Copilot CLI, Cursor CLI, Aider, Amp, Droid, Goose, Kiro CLI, Kilo CLI, OpenClaw, Hermes Agent, and Cline CLI.

## Install

### 1. Get the app

Download the `.dmg` from the [latest release](https://github.com/PunGrumpy/afterhours/releases/latest), open it, and drag Afterhours to Applications. The app isn't notarized yet, so the first time you open it, click **Open Anyway** in **System Settings > Privacy & Security**.

To build it yourself instead, you need macOS 14 or later and the Xcode Command Line Tools:

```bash
./apps/macos/scripts/build-app.sh --install
```

This builds a universal `Afterhours.app`, copies it to `/Applications`, and opens it. Leave off `--install` to build `apps/macos/build/Afterhours.app` only.

### 2. Keep it awake with the lid closed

When plugged in, a closed Mac stays awake without setup. On battery, macOS ignores keep-awake requests once you close the lid, so this step needs an admin password once. Open **Settings… > Power** and click **Install…** next to **Lid-closed mode**.

It adds `/etc/sudoers.d/afterhours`, which allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`, nothing else.

### 3. Connect your agents

Open **Settings… > Agents** and click **Install** for each Claude Code config directory (`~/.claude`, `~/.claude-*`), then restart open Claude Code sessions.

Hooks tell Afterhours when Claude Code is working, waiting for you, or idle. Agents without hooks count as working while their processes use at least 3% of a CPU core, and for 45 seconds after that.

Any tool with hooks or plugins can report its own state. Afterhours installs the hook binary at `~/Library/Application Support/Afterhours/bin/afterhours-hook`, not on your PATH, so call it by its full path:

```bash
"$HOME/Library/Application Support/Afterhours/bin/afterhours-hook" agent_id --state working --session session_id
```

`agent_id` is any of the ids Afterhours knows: `claude`, `codex`, `opencode`, `antigravity`, `gemini`, `copilot`, `cursor`, `aider`, `amp`, `droid`, `goose`, `kiro`, `kilo`, `openclaw`, `hermes`, `cline`, or any name you like. `--state` accepts `working`, `waiting`, `idle`, or `end`.

### 4. Launch at login

Turn on **Settings… > General > Launch at login**. Press `⌥⌘L` anywhere to turn Afterhours on or off.

## Waiting for your reply

When agents finish or ask you something, Afterhours keeps your Mac awake so you can reply, and remote clients like T3 Code or SSH stay connected:

- **Plugged in:** it waits until every agent session closes
- **On battery:** it waits up to 1 hour after an agent last worked, so a forgotten session can't drain the battery

Change both in **Settings… > Power**.

## Subscription limits

The menu shows how much of each subscription's rate-limit windows is left and when they reset, and colors each bar by where the current burn rate lands: blue with room to spare, orange inside the last tenth, red when it runs out before the reset. So you know before closing the lid whether tonight's work fits. It reads the logins the tools already keep and asks each provider for the numbers when you open the menu and every 5 minutes while agents work:

- **Claude Code**: the Keychain login, one per `~/.claude*` config directory
- **Codex**: `~/.codex/auth.json`
- **Cursor**: the Cursor app's state store, or `~/.cursor/auth.json`
- **Copilot**: `~/.config/github-copilot/apps.json` or the `gh` login
- **OpenCode Go**: `~/.local/share/opencode/auth.json`
- **Grok Build**: `~/.grok/auth.json`

Afterhours never stores or refreshes a login. If one expires, run that tool once. Turn it off in **Settings… > Limits**.

If you pool accounts on a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) hub, add it under **Settings… > Limits > Usage providers** with its URL and management key. Its accounts join the menu, pooled per provider like T3 Code's Limits page: one bar per window with a segment per account. The key is kept in your Keychain, and Afterhours only reads through the hub.

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

Afterhours has no telemetry, analytics, crash reporting, or update checks. It reads process names and command lines to spot agents, and never reads your code or terminal output.

The only network requests are the subscription checks described above. They run only while **Settings… > Limits > Show subscription limits in the menu** is on, which is the default. Each request sends a login your tool already stores on your Mac to that tool's own vendor. It reads, never writes, and runs when you open the menu and every 5 minutes while agents work:

| Provider | Login it reads | Where it's sent |
| --- | --- | --- |
| Claude Code | Keychain login, one per `~/.claude*` directory | `api.anthropic.com` |
| Codex | `~/.codex/auth.json` | `chatgpt.com` |
| OpenCode Go | OpenCode's `auth.json` | `opencode.ai` |
| Copilot | `~/.config/github-copilot/apps.json` or the `gh` login | `api.github.com`, presented as Copilot Chat |
| Cursor | the Cursor app's state store or `~/.cursor/auth.json` | `api2.cursor.sh` |
| Grok Build | `~/.grok/auth.json` | `cli-chat-proxy.grok.com` |
| CLIProxyAPI hubs you add | the management key you enter | the hub's URL |

Afterhours never stores, refreshes, or forwards a login anywhere else. Turn the setting off, and no request goes out at all.

The hook receives each event Claude Code sends and keeps only these fields in `~/Library/Application Support/Afterhours/sessions/`:

- Session ID and agent name
- State: working, waiting, or idle
- Agent process ID and working directory
- Time of the last event

Afterhours deletes a session's file when its agent exits.

## Uninstall

Remove the system changes before deleting the app:

1. Click **Settings… > Power > Uninstall** to remove the sudoers rule.
2. Click **Settings… > Agents > Remove** for each config directory. This leaves a copy of your previous file as `settings.json.afterhours-backup` next to each `settings.json`. Delete it once you're happy with the result.
3. Click **Settings… > Limits > Remove** next to each hub. This deletes its management key from your Keychain.
4. Turn off **Settings… > General > Launch at login**.
5. Delete the app, `~/Library/Application Support/Afterhours`, and its preferences: `defaults delete app.afterhours.local`.

Agent logos in `apps/macos/Resources/agents/` come from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT) and each vendor's own site. They're trademarks of their owners.

## License

[MIT](LICENSE)
