#!/bin/sh
# Cases for turn-budget.sh: the notes at three quarters of the turn limit and at it, the refusal of tool calls at it, and the limit that the parent changes meanwhile. Run: sh hooks/turn-budget.test.sh
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
hook="$hooks_dir/turn-budget.sh"
real_root="$(cd "$hooks_dir/.." && pwd)"
post_json="$hooks_dir/fixtures/post-tool-batch.json"
pre_json="$hooks_dir/fixtures/pre-tool-use.json"
# The hook and the live plugin read the real state directory, so the test keeps to directories of its own.
tmp=$(mktemp -d)
mkdir "$tmp/data" "$tmp/config" "$tmp/tmp"
CLAUDE_PLUGIN_DATA="$tmp/data"; CLAUDE_CONFIG_DIR="$tmp/config"; TMPDIR="$tmp/tmp"; CLAUDE_CODE_SESSION_ID=fake-session
export CLAUDE_PLUGIN_DATA CLAUDE_CONFIG_DIR TMPDIR CLAUDE_CODE_SESSION_ID
unset XDG_RUNTIME_DIR
state="$CLAUDE_PLUGIN_DATA/agent-orchestration-bash-output"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}

# A fixture plugin root with its own table of turn limits. x has a limit of 8 (the first note comes at 6), y of 10 (at 8, since 7.5 rounds up), z of 4 (at 3), s of 1 and t of 2 (the two notes would be one round, and the one for the limit comes); v has a row with no number, u a row of 0, and nolimit has no row.
root=$(mktemp -d); mkdir "$root/references"
printf '# agent\tturn limit\nx\t8\ny\t10\nz\t4\ns\t1\nt\t2\nv\tlots\nu\t0\n' > "$root/references/turn-limits.tsv"

# The texts, as the hook must print them.
near_text() { printf 'This subagent run has made %s tool rounds of its turn limit of %s. At the limit its tool calls are refused and the run returns its report; the parent can raise the limit and resume the run with its context.' "$1" "$2"; }
at_text() { printf 'This subagent run has made %s tool rounds, its turn limit. Its tool calls are now refused, so its next message is its report: what is done and what is left. The parent can raise the limit and resume the run with its context.' "$1"; }
deny_text() { printf 'This subagent run has made %s tool rounds and its turn limit is %s, so this tool call is refused. The run ends with its report of what is done and what is left; the parent can raise the limit and resume the run with its context.' "$1" "$2"; }

fire() { # event session agent type root tool; prints what the hook printed. An empty session, agent or tool is left out of the input.
  jq -n --arg e "$1" --arg s "$2" --arg a "$3" --arg t "$4" --arg l "$6" '{hook_event_name: $e} + (if $s == "" then {} else {session_id: $s} end) + (if $a == "" then {} else {agent_id: $a, agent_type: $t} end) + (if $l == "" then {} else {tool_name: $l} end)' | CLAUDE_PLUGIN_ROOT="$5" ${HOOK_SH:-sh} "$hook"
}
batch() { fire PostToolBatch "$1" "$2" "$3" "$4" ""; } # session agent type root
pre() { fire PreToolUse "$1" "$2" "$3" "$4" "${5:-Bash}"; } # session agent type root [tool]
rounds() { # n session agent type root; fires PostToolBatch n times and keeps nothing
  n=$1; shift
  while [ "$n" -gt 0 ]; do batch "$@" > /dev/null; n=$((n - 1)); done
}
silent() { # command...; the command exits 0 and prints nothing
  out=$("$@"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
is_context() { # output text; JSON for PostToolBatch whose additionalContext is the text
  printf '%s' "$1" | jq -e --arg t "$2" '.hookSpecificOutput | .hookEventName == "PostToolBatch" and .additionalContext == $t' > /dev/null
}
is_deny() { # output text; JSON for PreToolUse that denies the call with the text as its reason
  printf '%s' "$1" | jq -e --arg t "$2" '.hookSpecificOutput | .hookEventName == "PreToolUse" and .permissionDecision == "deny" and .permissionDecisionReason == $t' > /dev/null
}
batch_says() { # text session agent type root; PostToolBatch exits 0 with that context
  text=$1; shift
  out=$(batch "$@"); rc=$?
  [ "$rc" = 0 ] && is_context "$out" "$text"
}
pre_denies() { # text session agent type root [tool]; PreToolUse exits 0 with that refusal
  text=$1; shift
  out=$(pre "$@"); rc=$?
  [ "$rc" = 0 ] && is_deny "$out" "$text"
}
factual() { # output; the text has no word of an order or of urgency
  ! printf '%s' "$1" | jq -r '.hookSpecificOutput | .additionalContext // .permissionDecisionReason' | grep -q -i -w -E 'must|should|please|hurry|wrap up|finish|stop now'
}
counter() { cat "$state/$1" 2>/dev/null; }
none_for() { [ -z "$(ls "$state" 2>/dev/null | grep "^$1")" ]; }
set_limit() { printf '%s\n' "$2" > "$state/$1"; } # file value

# The main conversation and the agent types of no plugin of this one are left alone, whatever the event.
for event in PostToolBatch PreToolUse; do
  check "$event: the main conversation prints nothing" silent fire $event s1 "" "" "$root" Bash
  check "$event: an agent type of no plugin prints nothing" silent fire $event s1 a1 general-purpose "$root" Bash
  check "$event: another plugin's agent type prints nothing" silent fire $event s1 a1 other-plugin:x "$root" Bash
  check "$event: a plugin prefix with no name prints nothing" silent fire $event s1 a1 agent-orchestration: "$root" Bash
  check "$event: an agent id without a type prints nothing" silent fire $event s1 a1 "" "$root" Bash
  check "$event: a bare agent name without the prefix prints nothing" silent fire $event s1 a1 x "$root" Bash
done
check "an event of no interest prints nothing" silent fire Stop s1 a1 agent-orchestration:x "$root" Bash
check "the state directory is not even created for any of these" [ ! -d "$state" ]
# A type of this plugin that no limit applies to is left alone too: nothing is counted and nothing is printed.
for event in PostToolBatch PreToolUse; do
  check "$event: a type with no row in the table and no override prints nothing" silent fire $event s1 a1 agent-orchestration:nolimit "$root" Bash
  check "$event: a row that is no number prints nothing" silent fire $event s1 a1 agent-orchestration:v "$root" Bash
  check "$event: a row of 0 prints nothing" silent fire $event s1 a1 agent-orchestration:u "$root" Bash
done
check "none of these leaves a counter" none_for s1

# One run through its limit of 8: the note at 6, the note and the refusal at 8.
check "round 1 prints nothing" silent batch s2 a1 agent-orchestration:x "$root"
check "round 1 leaves a counter of the count and the type name in the state directory" [ "$(counter s2.turns.a1)" = "1 x" ]
check "PreToolUse below the limit prints nothing" silent pre s2 a1 agent-orchestration:x "$root"
rounds 4 s2 a1 agent-orchestration:x "$root"
check "round 5, below the note, left a counter of 5" [ "$(counter s2.turns.a1)" = "5 x" ]
note=$(batch s2 a1 agent-orchestration:x "$root")
check "round 6, three quarters of 8, says the count and the limit" is_context "$note" "$(near_text 6 8)"
check "that note states facts and orders nothing" factual "$note"
check "round 7 prints nothing" silent batch s2 a1 agent-orchestration:x "$root"
check "PreToolUse at 7 of 8 prints nothing" silent pre s2 a1 agent-orchestration:x "$root"
note=$(batch s2 a1 agent-orchestration:x "$root")
check "round 8, the limit itself, says the tool calls are now refused" is_context "$note" "$(at_text 8)"
check "that note states facts and orders nothing" factual "$note"
check "PreToolUse never counts" [ "$(counter s2.turns.a1)" = "8 x" ]
deny=$(pre s2 a1 agent-orchestration:x "$root")
check "PreToolUse at the limit denies, with the count and the limit in the reason" is_deny "$deny" "$(deny_text 8 8)"
check "that reason states facts and orders nothing" factual "$deny"
check "PreToolUse denies a Read too" pre_denies "$(deny_text 8 8)" s2 a1 agent-orchestration:x "$root" Read
check "PreToolUse denies an Agent call too" pre_denies "$(deny_text 8 8)" s2 a1 agent-orchestration:x "$root" Agent
check "PreToolUse denies an MCP tool too" pre_denies "$(deny_text 8 8)" s2 a1 agent-orchestration:x "$root" mcp__server__tool
check "PreToolUse never refuses StructuredOutput" silent pre s2 a1 agent-orchestration:x "$root" StructuredOutput
check "a refusal counts nothing" [ "$(counter s2.turns.a1)" = "8 x" ]
check "round 9, past the limit, prints nothing" silent batch s2 a1 agent-orchestration:x "$root"
check "PreToolUse past the limit says the count it has" pre_denies "$(deny_text 9 8)" s2 a1 agent-orchestration:x "$root"
rounds 4 s2 a1 agent-orchestration:x "$root"
check "the count keeps rising, past the limit too" [ "$(counter s2.turns.a1)" = "13 x" ]
check "PreToolUse never refuses StructuredOutput past the limit either" silent pre s2 a1 agent-orchestration:x "$root" StructuredOutput

# The limit is read from the table, per agent type.
rounds 6 s3 a1 agent-orchestration:y "$root"
check "a limit of 10: round 7 prints nothing" silent batch s3 a1 agent-orchestration:y "$root"
check "a limit of 10: round 8 is the first note, 7.5 rounded up" batch_says "$(near_text 8 10)" s3 a1 agent-orchestration:y "$root"
check "a limit of 10: round 9 prints nothing" silent batch s3 a1 agent-orchestration:y "$root"
check "a limit of 10: PreToolUse at 9 prints nothing" silent pre s3 a1 agent-orchestration:y "$root"
check "a limit of 10: round 10 is the limit" batch_says "$(at_text 10)" s3 a1 agent-orchestration:y "$root"
check "a limit of 10: PreToolUse at 10 denies" pre_denies "$(deny_text 10 10)" s3 a1 agent-orchestration:y "$root"
rounds 2 s4 a1 agent-orchestration:z "$root"
check "a limit of 4: the first note comes at 3" batch_says "$(near_text 3 4)" s4 a1 agent-orchestration:z "$root"
check "a limit of 4: round 4 is the limit" batch_says "$(at_text 4)" s4 a1 agent-orchestration:z "$root"
check "a limit of 1: round 1 says only that it is the limit" batch_says "$(at_text 1)" s4 a2 agent-orchestration:s "$root"
check "a limit of 1: PreToolUse denies at once" pre_denies "$(deny_text 1 1)" s4 a2 agent-orchestration:s "$root"
rounds 1 s4 a3 agent-orchestration:t "$root"
check "a limit of 2: round 2 says only that it is the limit" batch_says "$(at_text 2)" s4 a3 agent-orchestration:t "$root"
check "a run with no counter yet is not refused" silent pre s4 a9 agent-orchestration:s "$root"

# The limit of the run beats the limit of the type in this session, which beats the table; a file that holds no positive number does not count.
set_limit s5.typelimit.x 20
rounds 8 s5 a1 agent-orchestration:x "$root"
check "a session limit of 20 for the type: 8 rounds are not refused" silent pre s5 a1 agent-orchestration:x "$root"
check "a session limit of 20: the first note comes at 15, not 6" [ "$(rounds 6 s5 a1 agent-orchestration:x "$root"; counter s5.turns.a1)" = "14 x" ]
check "a session limit of 20: round 15 says it" batch_says "$(near_text 15 20)" s5 a1 agent-orchestration:x "$root"
rounds 4 s5 a1 agent-orchestration:x "$root"
check "a session limit of 20: round 20 is the limit" batch_says "$(at_text 20)" s5 a1 agent-orchestration:x "$root"
check "a session limit of 20: PreToolUse at 20 denies, naming 20" pre_denies "$(deny_text 20 20)" s5 a1 agent-orchestration:x "$root"
check "a second run of the type, with no counter yet, has the session limit too" silent pre s5 a2 agent-orchestration:x "$root"
rounds 8 s5 a2 agent-orchestration:x "$root"
check "a second run of the type is not refused at the table's 8" silent pre s5 a2 agent-orchestration:x "$root"
set_limit s5.limit.a1 3
check "a limit of 3 for the run beats the session's 20" pre_denies "$(deny_text 20 3)" s5 a1 agent-orchestration:x "$root"
check "the run's limit leaves the second run of the type on the session's 20" silent pre s5 a2 agent-orchestration:x "$root"
set_limit s5.limit.a1 abc
check "a run limit that is no number falls back to the session's 20" silent pre s5 a2 agent-orchestration:x "$root"
check "a run limit that is no number falls back to the session's 20, for the run it names too" pre_denies "$(deny_text 20 20)" s5 a1 agent-orchestration:x "$root"
set_limit s5.limit.a1 0
check "a run limit of 0 falls back to the session's 20" pre_denies "$(deny_text 20 20)" s5 a1 agent-orchestration:x "$root"
set_limit s5.typelimit.x 0
check "a session limit of 0 falls back to the table's 8" pre_denies "$(deny_text 20 8)" s5 a1 agent-orchestration:x "$root"
set_limit s5.typelimit.y 2
check "another type's session limit changes nothing for this one" pre_denies "$(deny_text 20 8)" s5 a1 agent-orchestration:x "$root"
set_limit s6.typelimit.nolimit 5
rounds 4 s6 a1 agent-orchestration:nolimit "$root"
check "a type with no row in the table gets a limit from a session limit" silent pre s6 a1 agent-orchestration:nolimit "$root"
check "that limit names its source: round 5 is the limit" batch_says "$(at_text 5)" s6 a1 agent-orchestration:nolimit "$root"
set_limit s6.limit.a2 2
rounds 2 s6 a2 agent-orchestration:nolimit "$root"
check "a limit for the run alone limits a type with no row and no session limit" pre_denies "$(deny_text 2 2)" s6 a2 agent-orchestration:nolimit "$root"
check "the session limit of one session does not reach another" silent pre s7 a1 agent-orchestration:nolimit "$root"

# The parent changes the limit of a run that was refused.
rounds 8 s8 a1 agent-orchestration:x "$root"
check "the run is at its limit of 8 and refused" pre_denies "$(deny_text 8 8)" s8 a1 agent-orchestration:x "$root"
set_limit s8.limit.a1 20
check "after the limit is raised to 20 the next call goes through" silent pre s8 a1 agent-orchestration:x "$root"
rounds 6 s8 a1 agent-orchestration:x "$root"
check "round 15 gives the note for the new limit" batch_says "$(near_text 15 20)" s8 a1 agent-orchestration:x "$root"
rounds 4 s8 a1 agent-orchestration:x "$root"
check "round 20 gives the note for the new limit" batch_says "$(at_text 20)" s8 a1 agent-orchestration:x "$root"
check "and the refusal comes at the new limit" pre_denies "$(deny_text 20 20)" s8 a1 agent-orchestration:x "$root"
rounds 3 s8 a2 agent-orchestration:x "$root"
set_limit s8.limit.a2 2
check "lowering the limit below the count refuses the next call" pre_denies "$(deny_text 3 2)" s8 a2 agent-orchestration:x "$root"
check "a round past a lowered limit prints nothing" silent batch s8 a2 agent-orchestration:x "$root"
check "the lowered limit keeps refusing" pre_denies "$(deny_text 4 2)" s8 a2 agent-orchestration:x "$root"
rm -f "$state/s8.limit.a2"
check "removing the run's limit puts the table's 8 back, so a count of 4 goes through" silent pre s8 a2 agent-orchestration:x "$root"

# A counter of the old format holds the count alone; a counter that is no number starts again.
printf '7\n' > "$state/s9.turns.a1"
check "an old counter of 7 reads as 7: the next call is not refused" silent pre s9 a1 agent-orchestration:x "$root"
check "an old counter of 7 reads as 7: round 8 is the limit" batch_says "$(at_text 8)" s9 a1 agent-orchestration:x "$root"
check "an old counter is rewritten in the new format" [ "$(counter s9.turns.a1)" = "8 x" ]
printf '8\n' > "$state/s9.turns.a2"
check "an old counter of 8 is refused" pre_denies "$(deny_text 8 8)" s9 a2 agent-orchestration:x "$root"
printf '09\n' > "$state/s9.turns.a3"
check "a counter with a leading zero reads as decimal: 09 and one more round is the limit of 10" batch_says "$(at_text 10)" s9 a3 agent-orchestration:y "$root"
printf 'garbage\n' > "$state/s10.turns.a1"
check "a counter that is no number starts again" silent batch s10 a1 agent-orchestration:x "$root"
check "a counter that is no number is rewritten as 1" [ "$(counter s10.turns.a1)" = "1 x" ]
printf 'garbage\n' > "$state/s10.turns.a2"
check "PreToolUse reads a counter that is no number as 0, even where a limit of 1 would refuse a count of 1" silent pre s10 a2 agent-orchestration:s "$root"

# Counters are kept apart, by agent and by session.
rounds 5 s11 a1 agent-orchestration:x "$root"
rounds 3 s11 a2 agent-orchestration:x "$root"
check "two agents of one session are counted apart: a1 is at 5" [ "$(counter s11.turns.a1)" = "5 x" ]
check "two agents of one session are counted apart: a2 is at 3" [ "$(counter s11.turns.a2)" = "3 x" ]
check "a1 reaches the first note on its own count" batch_says "$(near_text 6 8)" s11 a1 agent-orchestration:x "$root"
check "a2 is nowhere near it" silent batch s11 a2 agent-orchestration:x "$root"
rounds 2 s12 a1 agent-orchestration:x "$root"
check "the same agent id in another session starts at 1" [ "$(counter s12.turns.a1)" = "2 x" ]

# Real agents: with no CLAUDE_PLUGIN_ROOT the hook reads the table of the checkout it lives in.
printf '44 reader\n' > "$state/s13.turns.a1"
check "the reader's row puts the first note at round 45, of a limit of 60" batch_says "$(near_text 45 60)" s13 a1 agent-orchestration:reader ""
check "round 46 of the reader prints nothing" silent batch s13 a1 agent-orchestration:reader ""
printf '59 reader\n' > "$state/s13.turns.a2"
check "round 60 of the reader is its limit" batch_says "$(at_text 60)" s13 a2 agent-orchestration:reader ""
check "and the reader's next call is refused" pre_denies "$(deny_text 60 60)" s13 a2 agent-orchestration:reader ""
printf '359 builder-m\n' > "$state/s13.turns.a3"
check "round 360 of builder-m is its limit" batch_says "$(at_text 360)" s13 a3 agent-orchestration:builder-m ""

# The recorded payloads of a subagent, the type changed to one of this plugin's.
recorded() { # payload-file jq-filter; the hook's output for the recorded payload after the filter
  jq -c "$2" "$1" | CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"
}
session=$(jq -r .session_id "$post_json")
agent=$(jq -r .agent_id "$post_json")
check "the recorded payloads are of one subagent in one session" [ "$session $agent" = "$(jq -r '.session_id + " " + .agent_id' "$pre_json")" ]
check "the recorded PreToolUse names a tool" [ "$(jq -r .tool_name "$pre_json")" = Bash ]
recorded "$post_json" '.agent_type = "agent-orchestration:x"' > /dev/null
check "the recorded PostToolBatch counts under its own session and agent" [ "$(counter "$session.turns.$agent")" = "1 x" ]
for round in 2 3 4 5; do recorded "$post_json" '.agent_type = "agent-orchestration:x"' > /dev/null; done
note=$(recorded "$post_json" '.agent_type = "agent-orchestration:x"')
check "the recorded PostToolBatch reaches the first note at round 6" is_context "$note" "$(near_text 6 8)"
check "the recorded PreToolUse below the limit prints nothing" silent recorded "$pre_json" '.agent_type = "agent-orchestration:x"'
recorded "$post_json" '.agent_type = "agent-orchestration:x"' > /dev/null
note=$(recorded "$post_json" '.agent_type = "agent-orchestration:x"')
check "the recorded PostToolBatch reaches the limit at round 8" is_context "$note" "$(at_text 8)"
deny=$(recorded "$pre_json" '.agent_type = "agent-orchestration:x"')
check "the recorded PreToolUse at the limit is denied" is_deny "$deny" "$(deny_text 8 8)"
check "the recorded PreToolUse of StructuredOutput is not" silent recorded "$pre_json" '.agent_type = "agent-orchestration:x" | .tool_name = "StructuredOutput"'
ignored() { # payload-file jq-filter; the filtered payload prints nothing and the counter stays at 8
  [ -z "$(recorded "$1" "$2")" ] && [ "$(counter "$session.turns.$agent")" = "8 x" ]
}
check "the recorded PostToolBatch as recorded (type general-purpose) prints nothing and counts nothing" ignored "$post_json" .
check "the recorded PreToolUse as recorded (type general-purpose) prints nothing" ignored "$pre_json" .
check "the recorded PostToolBatch without agent_id (the main conversation) prints nothing and counts nothing" ignored "$post_json" 'del(.agent_id, .agent_type)'
check "the recorded PreToolUse without agent_id (the main conversation) prints nothing" ignored "$pre_json" 'del(.agent_id, .agent_type)'

# Input that must never fail a round.
bad_input() { # stdin text; the hook exits 0 and prints nothing
  out=$(printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "empty input exits 0 and prints nothing" bad_input ''
check "input that is no JSON exits 0 and prints nothing" bad_input 'not json {'
for event in PostToolBatch PreToolUse; do
  check "$event: an unsafe session id prints nothing" silent fire $event '../s14' a1 agent-orchestration:x "$root" Bash
  check "$event: an unsafe agent id prints nothing" silent fire $event s14 '../a1' agent-orchestration:x "$root" Bash
  check "$event: an unsafe agent name prints nothing" silent fire $event s14 a1 'agent-orchestration:../x' "$root" Bash
  check "$event: no session id prints nothing" silent fire $event "" a1 agent-orchestration:x "$root" Bash
done
check "an unsafe session id, agent id or agent name writes nothing" none_for s14
nameless() { # a PreToolUse payload with no tool_name, at the limit
  out=$(fire PreToolUse s2 a1 agent-orchestration:x "$root" ""); rc=$?
  [ "$rc" = 0 ] && is_deny "$out" "$(deny_text 13 8)"
}
check "PreToolUse without a tool name at the limit is refused, as it cannot be StructuredOutput" nameless

# No directory to keep a counter in, and no jq.
no_dir() { # event
  out=$(jq -n --arg e "$1" '{hook_event_name: $e, tool_name: "Bash", session_id: "s15", agent_id: "a1", agent_type: "agent-orchestration:x"}' | env -u CLAUDE_PLUGIN_DATA -u XDG_RUNTIME_DIR -u TMPDIR CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "PostToolBatch: with no directory for a counter the hook exits 0 and prints nothing" no_dir PostToolBatch
check "PreToolUse: with no directory for a counter the hook exits 0 and prints nothing" no_dir PreToolUse
sh_bin=$(command -v "${HOOK_SH:-sh}")
no_jq() { # event
  out=$(jq -n --arg e "$1" '{hook_event_name: $e, tool_name: "Bash", session_id: "s2", agent_id: "a1", agent_type: "agent-orchestration:x"}' | PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$root" "$sh_bin" "$hook"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ]
}
check "PostToolBatch: without jq the hook exits 0 and prints nothing" no_jq PostToolBatch
check "PreToolUse: without jq the hook exits 0 and prints nothing, even at the limit" no_jq PreToolUse
unwritable() { # the counter cannot be written: the hook exits 0 and prints nothing
  mkdir "$state/s16.turns.a1" 2>/dev/null
  silent batch s16 a1 agent-orchestration:s "$root"
}
check "a counter that cannot be written exits 0 and prints nothing" unwritable

rm -rf "$tmp" "$root"
exit $fail
