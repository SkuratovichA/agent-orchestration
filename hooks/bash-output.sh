#!/bin/sh
# PreToolUse on Bash, for the main conversation only: whatever a command prints there is re-read on every
# later request. A command whose text does not bound its own output is refused once, with the ways to bound
# it; the same command sent again runs. A subagent's Bash passes untouched, because reading whole output and
# returning the facts is what a subagent is for.
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
IFS='|' read -r agent background session <<EOF
$(printf '%s' "$input" | jq -r '"\(.agent_id // "")|\(.tool_input.run_in_background // false)|\(.session_id // "none")"')
EOF
[ -n "$agent" ] && exit 0
[ "$background" = true ] && exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' | tr '\n' ' ' | sed 's/[[:space:]]*$//')
[ -n "$command" ] || exit 0

# Bounded by its own text: the last stage or statement is a filter that caps the output, or stdout ends in a file.
# Only the end of the command is looked at; an earlier statement of a list is not checked.
cap='(^|[|;&])[[:space:]]*(head|tail|wc|grep[[:space:]]+-[A-Za-z]*[cq][A-Za-z]*)([[:space:]][^|;&]*)?$'
file='((^|[^2&>])>>?|&>>?)[[:space:]]*[^[:space:]&|;<>]+([[:space:]]+2>&1)?$'
printf '%s' "$command" | grep -Eq "$cap|$file" && exit 0

# Asked once per distinct command and session. If the mark cannot be written the hook lets the call through,
# because a refusal that can never be answered would block the command for good.
state="${TMPDIR:-/tmp}/claude-bash-output-asked"
mark="$state/$session-$(printf '%s' "$command" | cksum | tr -cd '0-9')"
[ -f "$mark" ] && exit 0
mkdir -p "$state" 2>/dev/null && : > "$mark" 2>/dev/null || exit 0
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Nothing in this command bounds its output, and what it prints stays in the main conversation and is re-read on every later request. Do one of three things. Hand the command to an agent-orchestration:reader and ask for the facts you need. Or bound it and run that instead: send stdout to a file and read the part you need, or end the pipeline in head, tail, wc or grep -c. Or, if you are certain it prints only a few lines, send the same command again unchanged and it will run."}}'
