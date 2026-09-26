---
"@afterhours/macos": patch
---

Installing or removing Claude Code hooks no longer overwrites your `settings.json` when it isn't valid JSON. You'll see an error instead, and your file stays untouched. Afterhours now keeps a fresh `settings.json.afterhours-backup` before every write, and writes through a symlinked `settings.json` instead of replacing it. The hook CLI ignores an unrecognized `--state` value instead of treating it as working, and the menu shows an error if the hook binary fails to install at launch.
