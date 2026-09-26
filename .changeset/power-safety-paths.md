---
"@afterhours/macos": patch
---

A Mac docked to an external display with its lid closed now stays awake when agents finish, when you pause, and when you turn Afterhours off. Afterhours only puts a closed Mac to sleep when closing the lid would sleep it anyway. Stopping Afterhours with `kill` or `pkill` now turns lid-closed mode off before the app exits. A laptop whose battery can't be read no longer counts as plugged in.
