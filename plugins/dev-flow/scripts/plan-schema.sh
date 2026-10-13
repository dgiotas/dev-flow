# Value sets and finding codes for the plan contract; the single definition, sourced by plan-check.sh.
# Plain assignments only, no logic. Values reach awk through ENVIRON, never -v.
PLAN_STATUS="DRAFT|APPROVED|IN_PROGRESS|DONE"
PLAN_APPROVED="yes|no"
PLAN_VERBS="create|modify|delete|rename|test"
PLAN_RISK="low|medium|high"
PLAN_REQUIRED="Objective|Files|Test first|Test command|Done when"
PLAN_OPTIONAL="Change|Depends on|Risk"
PLAN_MAX_FILES=6
PLAN_PLACEHOLDER_WORDS="TBD|TODO"
PLAN_PLACEHOLDER_PHRASES="etc\.|as appropriate|similar to task [0-9]+|handle errors|update tests accordingly"
PLAN_BASELINE_COMMANDS="bash sh cd test [ true false echo printf cat grep awk sed tr cut sort uniq head tail wc diff cmp ls find xargs mkdir rm cp mv touch env jq git"
PLAN_CODES="crlf header-status header-approved header-spec spec-missing blocking-row tasks-missing task-heading task-number checkbox field-missing field-empty field-duplicate files-entry files-verb path-absolute path-dotdot path-missing path-exists depends-forward depends-malformed risk-value test-command-empty verify-toolchain placeholder deviation-line override-malformed unlisted-path too-many-files override-unused fence-unclosed"
PLAN_NO_OVERRIDE="blocking-row override-malformed override-unused fence-unclosed"
# An unresolved escalation is the Deviations line "- Task N: BLOCKED: <reason>"; the user resolves it by rewriting it as "- Task N: RESOLVED: <decision>".
PLAN_BLOCKED="BLOCKED"
export PLAN_BLOCKED PLAN_STATUS PLAN_APPROVED PLAN_VERBS PLAN_RISK PLAN_REQUIRED PLAN_OPTIONAL PLAN_MAX_FILES PLAN_PLACEHOLDER_WORDS PLAN_PLACEHOLDER_PHRASES PLAN_BASELINE_COMMANDS PLAN_CODES PLAN_NO_OVERRIDE
