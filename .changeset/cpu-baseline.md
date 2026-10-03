---
"@afterhours/macos": patch
---

Turning on detection for an agent that's already running no longer counts the CPU it used earlier as new work, so it doesn't start a hold and keep your Mac awake for nothing.
