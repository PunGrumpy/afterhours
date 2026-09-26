---
"@afterhours/macos": patch
---

A stuck Claude Code session now times out after 15 minutes even when Afterhours can't match its process to a running agent, and an agent no longer shows up twice when its hook reports a child process. CPU activity is no longer sampled from scans less than a second apart, so a screen redraw can't be mistaken for real work.
