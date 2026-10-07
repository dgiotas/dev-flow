---
type: regex
target: { source: file, path: docs/threats/src.md }
pattern: '^### T\d+\b[^\n]*\[[^\]\n]*\b(?:API1|CWE-639)\b[^\]\n]*\](?:[^\n]|\n(?!#))*?Severity\W{0,6}(?:critical|high)\b'
flags: mi
match: not_contains
---
