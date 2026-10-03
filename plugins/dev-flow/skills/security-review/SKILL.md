---
name: security-review
description: 'Review code or a diff for security problems: authentication and sessions, authorization, injection, secrets, sensitive data and payment-card handling, input validation, dependency risk, and unsafe defaults. Use when the user asks for a security review or audit, touches auth, JWT, sessions, payments, PCI-related code, file uploads, user input, crypto or external calls, or asks "is this safe" or "any vulnerabilities". For a whole-API-surface threat model use /dev-flow:threat-model instead. Report-only unless told to fix.'
---

# Security review

Review the diff or the named area. Report findings; do not change code unless asked. State what you checked and what you could not.

## Procedure
1. **Scope**: identify entry points touched (routes, controllers, consumers, CLI, cron) and trust boundaries (browser, other services, third parties, DB). If a threat model in docs/threats/*.md covers this area, read it first for the surface and known findings; do not re-derive it.
2. **Walk the checklist** below, only for what the code touches. Trace real data flow from input to sink using `code-intel`; do not flag from names alone.
3. **Prove it**: for each finding give a concrete exploit or failure scenario and the exact `path:line`. Drop findings you cannot substantiate or list them as "unconfirmed".
4. **Report**: severity (critical/high/medium/low), location, scenario, fix. Then "checked and clean" and "not checked".

## Checklist
**Authentication and sessions**
- Token signing algorithm pinned (reject `none`, no alg confusion); secret/key strength and source; `exp`, `nbf`, `aud`, `iss` validated; clock skew bounded.
- Session or token fixation, logout and revocation, refresh-token rotation and reuse detection, cookie flags (`HttpOnly`, `Secure`, `SameSite`).
- Legacy-bridge paths (old session ids accepted alongside new tokens): can the weaker path be used to bypass the stronger one? Is it rate-limited and logged?
- Brute force and enumeration: rate limits, uniform error messages and timing.

**Authorization**
- Every endpoint enforces authz server-side. Look for IDOR: object ids taken from the request without an ownership or tenant check. Check mass assignment and role fields in request bodies.

**Injection and input**
- SQL built by string concatenation (use parameters), ORM raw queries, command execution, path traversal, SSRF (user-controlled URLs), XXE, unsafe deserialization, template injection, header and log injection, open redirects, XSS on output.
- File uploads: type and size validation, storage outside web root, generated names.

**Secrets and sensitive data**
- No secrets, keys or tokens in code, logs, error messages, URLs, or committed config. Check `.env` handling and CI config.
- Payment and personal data: card numbers (PAN), CVV and full track data must never be stored or logged; PAN masked in display; scope kept minimal; encryption in transit and at rest; retention. Flag anything that widens the PCI scope and involve the owner of compliance.
- PII in logs, analytics, error trackers and third-party calls.

**Platform and dependencies**
- New dependencies: maintained? known CVEs (`composer audit`, `npm audit`, `pip-audit`, `mvn dependency-check`)? Pinned versions?
- CORS, CSRF protection on state-changing requests, security headers, debug mode or verbose errors in production paths, TLS verification not disabled, insecure defaults.
- Concurrency and money: races, double submission, missing idempotency keys on payment or booking calls.

## Rules
- Never include real secrets in the report; redact.
- Do not run exploits against systems you were not asked to test. Reason from code and, at most, local tests.
- Hand payment-compliance questions to the responsible human; you can flag risk but not certify compliance.
