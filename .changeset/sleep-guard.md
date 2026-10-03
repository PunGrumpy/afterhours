---
"@afterhours/macos": patch
---

If Afterhours crashes or you Force Quit it while it keeps a closed Mac awake on battery, a small helper now turns `pmset disablesleep` back off right away, so your Mac can sleep again instead of staying awake until Afterhours opens. During a hold, Afterhours also turns it back on if something else turned it off.
