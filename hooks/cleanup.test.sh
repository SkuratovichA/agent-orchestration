#!/bin/sh
# Cases for cleanup.sh. Run: sh hooks/cleanup.test.sh
hook="$(cd "$(dirname "$0")" && pwd)/cleanup.sh"
CLAUDE_PLUGIN_DATA=$(mktemp -d); export CLAUDE_PLUGIN_DATA
state="$CLAUDE_PLUGIN_DATA/agent-orchestration-bash-output"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}
exists() { [ -f "$state/$1" ]; }
absent() { [ ! -f "$state/$1" ]; }
seed() {
  rm -rf "$state"; mkdir -m 700 "$state"
  : > "$state/s1.111"; : > "$state/s1.222"; : > "$state/s2.333"; : > "$state/s3.444"
  touch -t 202001010000 "$state/s3.444"
}
end() { # stdin JSON
  printf '%s' "$1" | ${HOOK_SH:-sh} "$hook" > "$CLAUDE_PLUGIN_DATA/out" 2>&1
  rc=$?
  [ "$rc" = 0 ] && [ ! -s "$CLAUDE_PLUGIN_DATA/out" ]
}

seed
check "exit 0 and silent for a session end" end '{"session_id":"s1","reason":"other"}'
check "the ending session's markers are removed" absent s1.111
check "all of them" absent s1.222
check "another session's fresh marker stays" exists s2.333
check "a marker older than a day is removed whatever its session" absent s3.444

# The turn counters of turn-budget.sh sit in the same directory and go the same way.
seed
: > "$state/s1.turns.a1"; : > "$state/s1.turns.a2"; : > "$state/s2.turns.a1"; : > "$state/s3.turns.a1"
touch -t 202001010000 "$state/s3.turns.a1"
check "exit 0 and silent for a session end with counters" end '{"session_id":"s1","reason":"other"}'
check "the ending session's counter of one agent is removed" absent s1.turns.a1
check "and of another agent" absent s1.turns.a2
check "another session's fresh counter stays" exists s2.turns.a1
check "a counter older than a day is removed whatever its session" absent s3.turns.a1
check "the markers go the same way" absent s1.111

seed
check "exit 0 and silent without session_id" end '{"reason":"other"}'
check "no session_id removes nothing fresh" exists s1.111
check "no session_id removes nothing old either" exists s3.444

seed
check "exit 0 and silent for an unsafe session_id" end '{"session_id":"../s2","reason":"other"}'
check "an unsafe session_id removes nothing" exists s2.333
rm -rf "$CLAUDE_PLUGIN_DATA"
exit $fail
