#!/bin/sh
# PostToolBatch, for this plugin's own agent types only: counts the tool rounds of one subagent run and, once,
# when the count reaches three quarters of the agent's maxTurns, adds a factual note to its context. maxTurns
# is a runaway fence well above ordinary runs; the note says where the fence is and what happens at it, and
# orders nothing. The fence is read from the agent's frontmatter, so the number lives in one place. The counter
# is a file per session and agent in the private directory (lib.sh), and cleanup.sh removes it.
# This runs after every tool round of every session. The main conversation and any other agent type leave
# before a file is touched, and the payload is parsed by one jq call. The hook always exits 0, so it never
# fails a round.
command -v jq >/dev/null 2>&1 || exit 0
fields=$(jq -r '[.session_id // "", .agent_id // "", .agent_type // ""] | join("|")' 2>/dev/null)
session=${fields%%|*}
rest=${fields#*|}
agent=${rest%%|*}
type=${rest#*|}
[ -n "$agent" ] || exit 0
case "$type" in
  agent-orchestration:?*) name=${type#agent-orchestration:} ;;
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

# The fence is the maxTurns line of the agent's frontmatter, the lines between the first two "---".
set -f
file="${CLAUDE_PLUGIN_ROOT:-$here/..}/agents/$name.md"
[ -f "$file" ] || exit 0
fence=
marks=0
while IFS= read -r line; do
  case "$line" in
    ---*) marks=$((marks + 1)); [ "$marks" -lt 2 ] || break ;;
    maxTurns:*) set -- ${line#maxTurns:}; fence=$1; break ;;
  esac
done < "$file"
case "$fence" in
  ''|*[!0-9]*) exit 0 ;;
esac
[ "$fence" -gt 0 ] || exit 0

dir=$(state_dir) || exit 0
counter="$dir/$session.turns.$agent"
count=0
[ ! -f "$counter" ] || read -r count < "$counter"
case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac
count=$((count + 1))
printf '%s\n' "$count" > "$counter" 2>/dev/null || exit 0

# The note comes once, at three quarters of the fence rounded up.
if [ "$count" -eq $(((fence * 3 + 3) / 4)) ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolBatch","additionalContext":"This subagent run has made %s tool rounds. Claude Code stops a run after %s turns and returns its work to the parent marked partial; the parent can resume it with its context."}}\n' "$count" "$fence"
fi
exit 0
