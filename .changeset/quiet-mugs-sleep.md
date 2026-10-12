---
"@afterhours/macos": patch
---

Afterhours uses less power. It checks for agents every 15 seconds instead of every 4 when nothing is running, lets macOS group its wakeups with other apps, and no longer reads every process's arguments or every session file on each check. Hooked agents now show up right away instead of on the next check, and opening the menu refreshes your sessions.
