#!/bin/sh
# Cases for turn-budget.sh. Run: sh hooks/turn-budget.test.sh
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
hook="$hooks_dir/turn-budget.sh"
recorded_json="$hooks_dir/fixtures/post-tool-batch.json"
CLAUDE_PLUGIN_DATA=$(mktemp -d); export CLAUDE_PLUGIN_DATA
state="$CLAUDE_PLUGIN_DATA/agent-orchestration-bash-output"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}

# A fixture plugin root. x has a fence of 8 (the note comes at 6), y of 10 (at 8, since 7.5 rounds up), z of 4 with
# spaces around it (at 3); w has none in its frontmatter and a maxTurns line in its body; v has one that is no number.
root=$(mktemp -d); mkdir "$root/agents"
agent_file() { # name frontmatter-line body-line
  { printf -- '---\nname: %s\n' "$1"; [ -z "$2" ] || printf '%s\n' "$2"; printf -- '---\n\n%s\n' "$3"; } > "$root/agents/$1.md"
}
agent_file x 'maxTurns: 8' 'You are x.'
agent_file y 'maxTurns: 10' 'You are y.'
agent_file z 'maxTurns:    4  ' 'You are z.'
agent_file w '' 'maxTurns: 99'
agent_file v 'maxTurns: lots' 'You are v.'

fire() { # session agent type root; prints what the hook printed. An empty session or agent is left out of the input.
  jq -n --arg s "$1" --arg a "$2" --arg t "$3" '{hook_event_name: "PostToolBatch", tool_calls: []} + (if $s == "" then {} else {session_id: $s} end) + (if $a == "" then {} else {agent_id: $a, agent_type: $t} end)' | CLAUDE_PLUGIN_ROOT="$4" ${HOOK_SH:-sh} "$hook"
}
rounds() { # n session agent type root; fires the hook n times and keeps nothing
  n=$1; shift
  while [ "$n" -gt 0 ]; do fire "$@" > /dev/null; n=$((n - 1)); done
}
silent() { # session agent type root; the hook exits 0 and prints nothing
  out=$(fire "$@"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
is_note() { # output count fence; the output is JSON for PostToolBatch whose note holds the count and the fence
  printf '%s' "$1" | jq -e --arg c "made $2 tool rounds" --arg f "after $3 turns" '.hookSpecificOutput | .hookEventName == "PostToolBatch" and (.additionalContext | contains($c) and contains($f))' > /dev/null
}
noted() { # session agent type root count fence
  out=$(fire "$1" "$2" "$3" "$4"); rc=$?
  [ "$rc" = 0 ] && is_note "$out" "$5" "$6"
}
factual() { # output; the note has no word of an order or of urgency
  ! printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext' | grep -q -i -w -E 'must|should|please|hurry|wrap up|finish|stop now'
}
counter() { cat "$state/$1" 2>/dev/null; }
none_for() { [ -z "$(ls "$state" 2>/dev/null | grep "^$1")" ]; }

check "the main conversation prints nothing" silent s1 "" "" "$root"
check "an agent type of no plugin prints nothing" silent s1 a1 general-purpose "$root"
check "another plugin's agent type prints nothing" silent s1 a1 other-plugin:x "$root"
check "a plugin prefix with no name prints nothing" silent s1 a1 agent-orchestration: "$root"
check "an agent id without a type prints nothing" silent s1 a1 "" "$root"
rounds 5 s1 a1 x "$root"
check "a bare agent name with a fence in the plugin's agents, but no prefix, prints nothing at round 6" silent s1 a1 x "$root"
check "none of these leaves a counter" none_for s1
check "the state directory is not even created for the main conversation" [ ! -d "$state" ]

# One agent, from the first round past the note.
check "round 1 prints nothing" silent s2 a1 agent-orchestration:x "$root"
check "round 1 leaves a counter of 1 in the state directory" [ "$(counter s2.turns.a1)" = 1 ]
rounds 4 s2 a1 agent-orchestration:x "$root"
check "round 5, below the threshold of 6, left a counter of 5" [ "$(counter s2.turns.a1)" = 5 ]
note=$(fire s2 a1 agent-orchestration:x "$root")
check "round 6 is the threshold: valid JSON for PostToolBatch with the count and the fence" is_note "$note" 6 8
check "the note states facts and orders nothing" factual "$note"
check "round 7, after the threshold, prints nothing" silent s2 a1 agent-orchestration:x "$root"
check "round 8, the fence itself, prints nothing" silent s2 a1 agent-orchestration:x "$root"
rounds 5 s2 a1 agent-orchestration:x "$root"
check "the count keeps rising, past the fence too" [ "$(counter s2.turns.a1)" = 13 ]

# The fence is read from the agent's own file.
rounds 6 s3 a1 agent-orchestration:y "$root"
check "a fence of 10: round 7 prints nothing" silent s3 a1 agent-orchestration:y "$root"
check "a fence of 10: round 8 is the threshold, 7.5 rounded up" noted s3 a1 agent-orchestration:y "$root" 8 10
check "a fence of 10: round 9 prints nothing" silent s3 a1 agent-orchestration:y "$root"
rounds 2 s4 a1 agent-orchestration:z "$root"
check "a fence of 4, with spaces around it, puts the note at 3" noted s4 a1 agent-orchestration:z "$root" 3 4
check "a maxTurns line in the body is no fence" silent s5 a1 agent-orchestration:w "$root"
check "a fence that is no number prints nothing" silent s5 a1 agent-orchestration:v "$root"
check "an agent with no file prints nothing" silent s5 a1 agent-orchestration:nope "$root"
check "none of these counts" none_for s5

# Real agent files: with no CLAUDE_PLUGIN_ROOT the hook reads the checkout it lives in.
printf '44\n' > "$state/s6.turns.a1"
check "the reader's own file puts the note at round 45, of a fence of 60" noted s6 a1 agent-orchestration:reader "" 45 60
check "round 46 of the reader prints nothing" silent s6 a1 agent-orchestration:reader ""

# Counters are kept apart.
rounds 5 s7 a1 agent-orchestration:x "$root"
rounds 3 s7 a2 agent-orchestration:x "$root"
check "two agents of one session are counted apart: a1 is at 5" [ "$(counter s7.turns.a1)" = 5 ]
check "two agents of one session are counted apart: a2 is at 3" [ "$(counter s7.turns.a2)" = 3 ]
check "a1 reaches the threshold on its own count" noted s7 a1 agent-orchestration:x "$root" 6 8
check "a2 is nowhere near it" silent s7 a2 agent-orchestration:x "$root"
rounds 2 s8 a1 agent-orchestration:x "$root"
check "the same agent id in another session starts at 1" [ "$(counter s8.turns.a1)" = 2 ]

# The recorded payload of a subagent, its type changed to one of this plugin's; the second form is the main conversation's.
recorded() { jq -c "$1" "$recorded_json" | CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"; }
session=$(jq -r .session_id "$recorded_json")
agent=$(jq -r .agent_id "$recorded_json")
check "the recorded payload is a subagent's" [ -n "$agent" ]
recorded '.agent_type = "agent-orchestration:x"' > /dev/null
check "the recorded payload counts under its own session and agent" [ "$(counter "$session.turns.$agent")" = 1 ]
for round in 2 3 4 5; do recorded '.agent_type = "agent-orchestration:x"' > /dev/null; done
note=$(recorded '.agent_type = "agent-orchestration:x"')
check "the recorded payload reaches the note at round 6" is_note "$note" 6 8
ignored() { # jq filter; the filtered payload prints nothing and the counter stays at 6
  [ -z "$(recorded "$1")" ] && [ "$(counter "$session.turns.$agent")" = 6 ]
}
check "the recorded payload as recorded (type general-purpose) prints nothing and counts nothing" ignored .
check "the recorded payload without agent_id (the main conversation) prints nothing and counts nothing" ignored 'del(.agent_id, .agent_type)'

# Input that must never fail a round.
bad_input() { # stdin text; the hook exits 0 and prints nothing
  out=$(printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "empty input exits 0 and prints nothing" bad_input ''
check "input that is no JSON exits 0 and prints nothing" bad_input 'not json {'
check "an unsafe session id prints nothing" silent '../s9' a1 agent-orchestration:x "$root"
check "an unsafe agent id prints nothing" silent s9 '../a1' agent-orchestration:x "$root"
check "an unsafe agent name prints nothing" silent s9 a1 'agent-orchestration:../x' "$root"
check "an unsafe session id, agent id or agent name writes nothing" none_for s9
check "no session id prints nothing" silent "" a1 agent-orchestration:x "$root"
printf 'garbage\n' > "$state/s10.turns.a1"
check "a counter that is no number starts again" silent s10 a1 agent-orchestration:x "$root"
check "a counter that is no number is rewritten as 1" [ "$(counter s10.turns.a1)" = 1 ]

# No directory to keep a counter in, and no jq.
no_dir() {
  out=$(jq -n '{session_id: "s11", agent_id: "a1", agent_type: "agent-orchestration:x"}' | env -u CLAUDE_PLUGIN_DATA -u XDG_RUNTIME_DIR -u TMPDIR CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "with no directory for a counter the hook exits 0 and prints nothing" no_dir
sh_bin=$(command -v "${HOOK_SH:-sh}")
no_jq() {
  out=$(jq -n '{session_id: "s12", agent_id: "a1", agent_type: "agent-orchestration:x"}' | PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$root" "$sh_bin" "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "without jq the hook exits 0 and prints nothing" no_jq

rm -rf "$CLAUDE_PLUGIN_DATA" "$root"
exit $fail
