# Portfolio status metadata

This repository publishes portfolio-facing project metadata in:

- `.portfolio/status_en.json`
- `.portfolio/status_th.json`

Both files follow schema version 1 defined by `dexter-cnx/portfolio/docs/PROJECT_STATUS_CONTRACT.md`.

## Maintenance rule

When a feature, release, architecture change, or project status materially changes what should be shown in the public portfolio, update both locale files in the same PR whenever practical.

Keep the two files semantically aligned. Localize only human-facing text; versions, URLs, technical names, and status values should remain consistent.

## Safety

These files are public metadata. Never place API keys, credentials, customer data, private URLs, tokens, or other non-public information in them.
