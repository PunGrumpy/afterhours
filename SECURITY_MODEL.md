# Security model

This file describes who and what afterhours trusts, so security reviews and scans judge findings against it. To report a vulnerability, use GitHub's private advisory flow: https://github.com/PunGrumpy/afterhours/security/advisories/new

## System overview

Afterhours is a macOS menu-bar app that keeps the Mac awake while coding agents work. `apps/macos` holds the app and the `afterhours-hook` CLI that agent hooks call; `packages/core` holds shared process and usage logic.

## Components

| Component | Code | Distribution surface |
| --- | --- | --- |
| afterhours | `apps/macos` (app, `afterhours-hook`), `packages/core` | macOS app |
| CI/release | `.github/workflows/*` | macOS app |

## Assets

- Local OAuth tokens the usage readers load (GitHub CLI `hosts.yml`, Copilot, Cursor, OpenCode) and the CLIProxyAPI hub management key in the Keychain.
- Integrity of the released app.

Critical assets across the maintainer's projects, in the maintainer's words: secrets in CI of action users (Cursor API key, `GITHUB_TOKEN`); root privileges and network config on Macs running Peony; integrity of published npm packages and releases; pigo API availability; and the data of downstream apps that use the libraries (logs, vectors, LINE messages).

## Trust boundaries and entry points

- **Agent hooks → `afterhours-hook`**: event JSON from coding-agent hooks; session files on disk.
- **Usage readers → provider APIs**: tokens read from local files are sent to provider APIs and the hub.
- **Keychain**: secrets are saved through `/usr/bin/security`.

## Attackers that matter

- Another local process or user on the same Mac. The maintainer did not rule local attackers out.
- A supply-chain attacker targeting the release workflow.

## Existing controls

- Secrets are stored in the Keychain.

## Out of scope

- `apps/web` (marketing site).
- Across the maintainer's projects: docs and marketing sites, and bench and video packages.
