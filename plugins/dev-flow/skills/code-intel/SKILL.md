---
name: code-intel
description: Choose the right code-search and code-navigation tool before exploring a repository. Use this whenever you need to find where something is implemented, understand how a feature works across files, find callers or callees, assess the blast radius of a change, look up how a library works, or explore an unfamiliar codebase, even if the user just says "find", "where is", "how does X work", or "what would break if". Prefer this over blind grep or reading many files.
---

# Code intelligence routing

Explore with the cheapest tool that answers the question. Reading whole files is the last resort.

## Pick the tool

| Question | First choice | Fallback |
|---|---|---|
| "Where is X implemented?" / concept search ("where do we validate tokens") | `semble` MCP search | `grep -rn` / `rg` |
| Exact symbol, string, or config key | `rg` (ripgrep) | `grep -rn` |
| "Who calls X?" / "What does X call?" / "What breaks if I change X?" | `codegraph` MCP (`codegraph_explore`) | LSP find-references, then `rg` |
| Definition, type, diagnostics of a symbol | LSP tool if available | `rg` + read the file |
| How a third-party library or framework API works | `context7` MCP | official docs via web fetch |
| Behaviour visible only at runtime (UI, network, console) | `chrome-devtools` MCP | ask the user to run it |

## Procedure

1. State the question in one sentence. Decide if it is conceptual, exact, or structural.
2. Run the first-choice tool. If the MCP tool is not connected (check with `/mcp`), use the fallback and say so once.
3. Read only the top results: the specific functions or line ranges, not entire files.
4. For change-impact questions, always run the graph query before editing. List the callers you found and mention any you could not resolve (dynamic calls, reflection, DI containers, string-based routing, which static tools often miss).
5. Report findings with `path:line` references so the user can jump to them.

## Rules

- Never claim "nothing else uses this" from a single grep. Cross-check with the graph tool or a second search phrased differently.
- In PHP, Java/Spring and DI-heavy code, check container config, annotations, route files, and event listeners in addition to direct calls.
- Note when an index may be stale (`codegraph init` not run for this repo, or many uncommitted changes).
