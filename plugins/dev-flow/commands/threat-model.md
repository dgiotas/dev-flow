---
description: "Threat-model this repo's API surface with the Opus threat-modeler agent (read-only, offline) and save it to docs/threats/<slug>.md for human review. Report-only: writes no code."
argument-hint: '[scope: path, service or route prefix; default whole repo]'
model: sonnet
---

Threat-model: $ARGUMENTS

Use the `threat-modeler` subagent to do the analysis so it runs on the strong model even if this session was started on a cheaper one. It is read-only and offline, and it returns the whole threat model as its reply; you write the file.

Steps:

1. **Scope and slug.** The scope is `$ARGUMENTS`, or the whole repo when empty. The slug is the scope lowercased, with every run of characters outside `[a-z0-9]` replaced by `-` and leading/trailing `-` trimmed. Any empty slug becomes `repo`, whether the scope was empty or had no `[a-z0-9]` characters. Examples: `src` gives `src`, `/api/v2` gives `api-v2`, `../..` gives `repo`.
2. **Facts.** Run `date +%F` and `git rev-parse --short HEAD`, using `no-git` when that fails. Get the absolute repo root with `git rev-parse --show-toplevel`, falling back to `pwd`. Detect the guidance file (`AGENTS.md`, else `CLAUDE.md`, else none) and whether `.codegraph/` exists.
3. **Baseline check.** Make one `WebSearch` for the current OWASP API Security Top 10 edition. If an owasp.org result shows an edition newer than 2023, the baseline line is `OWASP API Security Top 10 <edition> (<url>); map to its IDs where the result lists them, else use 2023 IDs and say so`. If the search is unavailable, denied or inconclusive, the baseline line is `OWASP API Security Top 10 2023 (current edition not checked)`. Do not retry.
4. **Delegate** to `threat-modeler` with the scope, the date, the short commit sha, the baseline line, the guidance file path, whether `.codegraph/` exists, and the absolute `repo root`.
5. If the reply starts with `NO-SURFACE:`, tell the user the reason, write nothing, and stop.
6. If the whole reply is wrapped in a single ``` fence, strip exactly that outer fence (the opening and closing fence lines only) before checking and writing. Then, if the reply starts with `# Threat model:`, write it verbatim to `docs/threats/<slug>.md`, creating the directory if needed. An existing file is overwritten (git keeps history); say so. Any other reply: show it, write nothing, stop.
7. **Redaction check** (report-only). Run this on the written file:
   `grep -nEi -e '-----BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e '(^|[^0-9])[0-9]{13,19}([^0-9]|$)' -e '(password|passwd|secret|api[_-]?key|token)["'\'']?[[:space:]]*[:=][[:space:]]*["'\''][^]["'\''[:space:]][^"'\''[:space:]]{7,}' docs/threats/<slug>.md`
   The patterns match a private key header, an AWS access key id, a PAN-like number, and a quoted secret assignment (case-insensitive; a quoted value starting with `[`, such as the `[REDACTED]` marker, is not matched). If anything matches, show the lines and tell the user to redact them before committing. Do not edit the file.
8. **Summary.** Give the file path, the finding counts by severity and confidence, and the number of "Not checked" entries. Remind the user that "Reviewed by" stays blank until a human signs off, that the file should be committed through normal PR review, and that it is not a PCI substitute.

Never commit, push or open a PR. Do not edit application code. The threat-modeler has no file-writing tool by design; you are the only writer, and only of docs/threats/<slug>.md.
