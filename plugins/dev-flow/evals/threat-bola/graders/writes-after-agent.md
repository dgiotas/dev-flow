---
type: tool_order
before: { tool: Agent, input_match: '"subagent_type"\s*:\s*"(?:[\w-]+:)?threat-modeler"' }
after: { tool: Write, input_match: '"file_path"\s*:\s*"[^"]*docs/threats/src\.md"' }
arm: with-only
---
