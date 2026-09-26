---
"@afterhours/macos": patch
---

Lid-closed mode now writes its sudoers rule from the privileged step itself, so nothing else running as your user can change the rule while the password prompt is open.
