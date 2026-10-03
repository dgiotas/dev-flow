---
type: llm
focus: { source: file, path: docs/threats/src.md }
---
PASS if the document's finding about ownership/BOLA on GET /bookings/:id is marked "Confidence: unverified" and names @acme/policy-gateway (or its enforceOwnership middleware) as the control that could not be followed, in the finding or under "Not checked".
FAIL if that finding is marked "Confidence: verified", or if the middleware is not mentioned.
