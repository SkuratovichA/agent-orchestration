#!/bin/sh
# Enforces the turn limit of the subagent runs of this plugin's own agent types. The limit is a number of tool rounds that the parent session can change at any moment (bin/agent-turns): lib.sh turn_limit reads it on every call, from the run's own limit file, the session's limit for the agent type, or the default in references/turn-limits.tsv, so a change takes effect on the run's next tool call. The frontmatter maxTurns of the agents is only the hard ceiling above it.
# PostToolBatch counts the round in <session>.turns.<agent> of the private directory (lib.sh), which holds "<count> <agent type name>" on one line (an old counter holds the count alone), and adds a factual note to the run's context when the count reaches three quarters of the limit and when it reaches the limit. The notes come on equality, not from a stored flag, so a raised limit gets its own notes.
# PreToolUse refuses the run's tool calls with a reason once the count has reached the limit, so the run ends with its report; the parent can raise the limit and resume the run with its context. A StructuredOutput call is never refused, so a run that must return a schema can still return it. PreToolUse never counts.
# This runs on every tool call of every session. The main conversation and any other agent type leave before a file is touched, and the payload is parsed by one jq call. The hook always exits 0, so it never fails a round; anything it cannot read or write means no limit from this plugin.
command -v jq >/dev/null 2>&1 || exit 0
fields=$(jq -r '[.hook_event_name // "", .session_id // "", .agent_id // "", .agent_type // "", .tool_name // ""] | join("|")' 2>/dev/null)
event=${fields%%|*}
rest=${fields#*|}
session=${rest%%|*}
rest=${rest#*|}
agent=${rest%%|*}
rest=${rest#*|}
type=${rest%%|*}
tool=${rest#*|}
[ -n "$agent" ] || exit 0
case "$type" in
  agent-orchestration:?*) name=${type#agent-orchestration:} ;;
  *) exit 0 ;;
esac
case "$event" in
  PreToolUse) [ "$tool" != StructuredOutput ] || exit 0 ;;
  PostToolBatch) ;;
  *) exit 0 ;;
esac
# These three become parts of file names.
for id in "$session" "$agent" "$name"; do
  case "$id" in
    ''|*[!A-Za-z0-9_-]*) exit 0 ;;
  esac
done

here=$(dirname "$0")
. "$here/lib.sh"

dir=$(state_dir) || exit 0
counter="$dir/$session.turns.$agent"
count=0
[ ! -f "$counter" ] || read -r count _ < "$counter"
if positive_int "$count"; then count=$int; else count=0; fi

case "$event" in
  PreToolUse)
    # A run with no counter has made no round, and a limit is at least 1.
    [ "$count" -gt 0 ] || exit 0
    limit=$(turn_limit "${CLAUDE_PLUGIN_ROOT:-$here/..}" "$dir" "$session" "$agent" "$name") || exit 0
    limit=${limit% *}
    if [ "$count" -ge "$limit" ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This subagent run has made %s tool rounds and its turn limit is %s, so this tool call is refused. The run ends with its report of what is done and what is left; the parent can raise the limit and resume the run with its context."}}\n' "$count" "$limit"
    fi
    ;;
  PostToolBatch)
    limit=$(turn_limit "${CLAUDE_PLUGIN_ROOT:-$here/..}" "$dir" "$session" "$agent" "$name") || exit 0
    limit=${limit% *}
    count=$((count + 1))
    printf '%s %s\n' "$count" "$name" 2>/dev/null > "$counter" || exit 0
    # The notes come on equality: at three quarters of the limit rounded up, and at the limit. For a limit below 4 the two are the same round, and the note for the limit is the one that comes.
    if [ "$count" -eq "$limit" ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolBatch","additionalContext":"This subagent run has made %s tool rounds, its turn limit. Its tool calls are now refused, so its next message is its report: what is done and what is left. The parent can raise the limit and resume the run with its context."}}\n' "$count"
    elif [ "$count" -eq $(((limit * 3 + 3) / 4)) ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolBatch","additionalContext":"This subagent run has made %s tool rounds of its turn limit of %s. At the limit its tool calls are refused and the run returns its report; the parent can raise the limit and resume the run with its context."}}\n' "$count" "$limit"
    fi
    ;;
esac
exit 0
