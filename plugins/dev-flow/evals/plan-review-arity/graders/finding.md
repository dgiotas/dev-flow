---
type: llm
---
PASS if the reply's verdict is REVISE and a numbered finding says Task 3 calls displayName with one argument, displayName(user), while the real function at src/names.js line 3 is displayName(first, last, title), and says what goes wrong if the plan ships as written.
FAIL if the verdict is PASS, that finding is missing, or it cites a different signature.
