---
type: llm
focus: { source: file, path: docs/threats/src.md }
---
PASS if the document has a finding classified API1 (Broken Object Level Authorization / IDOR) for GET /bookings/:id that cites src/routes/bookings.js with a line number between 6 and 9 and is marked "Confidence: verified".
FAIL if there is no such finding, it cites another file, or it is marked unverified.
