---
type: regex
target: { source: file, path: docs/threats/src.md }
pattern: '^### T\d+\b[^\n]*\bAPI1\b[^\n]*Confidence:\s*verified\b'
flags: m
match: not_contains
---
