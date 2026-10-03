---
"@afterhours/macos": patch
---

Afterhours now cleans up before it exits when the terminal that started it closes, the same way it already did for `kill` and `pkill`, so lid-closed mode doesn't stay on. An error about installing the hook at launch also stays in the menu instead of disappearing the next time a hold starts or ends.
