---
type: regex
target: { source: file, path: docs/threats/src.md }
pattern: '^### T\d+\b[^\n]*\bAPI1\b[^\n]*Confidence:\s*verified\b(?:\n(?!##)[^\n]*)*?src/routes/bookings\.js:[6-9]\b'
flags: m
---
