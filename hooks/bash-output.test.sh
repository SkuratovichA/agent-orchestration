#!/bin/sh
# Cases for bash-output.sh. Run: sh hooks/bash-output.test.sh
hook="$(cd "$(dirname "$0")" && pwd)/bash-output.sh"
CLAUDE_PLUGIN_DATA=$(mktemp -d); export CLAUDE_PLUGIN_DATA
fail=0
run() { # session agent background command; an empty session is left out of the input
  jq -n --arg s "$1" --arg a "$2" --argjson b "$3" --arg c "$4" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c, run_in_background: $b}} + (if $s == "" then {} else {session_id: $s} end) + (if $a == "" then {} else {agent_id: $a} end)' | ${HOOK_SH:-sh} "$hook"
}
expect() { # want label session agent background command
  got=$(run "$3" "$4" "$5" "$6" | jq -r '.hookSpecificOutput.permissionDecision // "pass"' 2>/dev/null)
  [ -n "$got" ] || got=pass
  if [ "$got" = "$1" ]; then echo "ok    $2"; else echo "FAIL  $2: wanted $1, got $got"; fail=1; fi
}
expect deny "unbounded command in the main conversation" s1 "" false 'git log'
expect pass "the same command sent again" s1 "" false 'git log'
expect deny "the same command in another session" s2 "" false 'git log'
expect pass "a subagent's command" s1 a1 false 'git log --stat'
expect pass "a background command" s1 "" true 'pnpm dev'
expect pass "pipeline ending in head" s1 "" false 'git log --oneline | head -20'
expect pass "pipeline ending in tail after 2>&1" s1 "" false 'pnpm test 2>&1 | tail -30'
expect pass "pipeline ending in wc" s1 "" false 'find . -name "*.ts" | wc -l'
expect pass "grep -c alone" s1 "" false 'grep -c TODO src/index.ts'
expect pass "log to a file, then tail" s1 "" false 'pnpm test > /tmp/test.log 2>&1; tail -30 /tmp/test.log'
expect pass "stdout and stderr to a file" s1 "" false 'pnpm build > /tmp/build.log 2>&1'
expect pass "both streams with &>" s1 "" false 'pnpm build &> /tmp/build.log'
expect pass "append to a file" s1 "" false 'date >> /tmp/runs.txt'
expect pass "group piped into tail, over several lines" s1 "" false '{ git status
git diff; } | tail -40'
expect deny "only stderr goes to a file" s1 "" false 'ls -laR 2> /tmp/err.txt'
expect deny "stdout sent to stderr" s1 "" false 'ls -laR >&2'
expect deny "cut bounds the width, not the length" s1 "" false 'grep -rn foo . | cut -c1-200'
expect deny "head in the middle of the pipeline" s1 "" false 'head -5 a.txt | xargs cat'
expect deny "bounded statement followed by an unbounded one" s1 "" false 'git log | head -3; git diff'
expect pass "input without a command" s1 "" false ''
expect deny "recursive ls to /dev/stderr" s1 "" false 'ls -laR > /dev/stderr'
expect deny "recursive ls to /dev/tty" s1 "" false 'ls -laR > /dev/tty'
expect deny "tail -f" s1 "" false 'tail -f /var/log/app.log'
expect deny "tail -f at the end of a pipeline" s1 "" false 'pnpm dev 2>&1 | tail -f'
expect deny "head with a huge line count" s1 "" false 'git log | head -n 999999'
expect deny "head -NUM with a huge count" s1 "" false 'git log | head -5000'
expect deny "tail from line 2 on" s1 "" false 'cat big.txt | tail -n +2'
expect deny "head with a huge byte count" s1 "" false 'cat a.bin | head -c 999999'
expect deny "grep -m with a huge count" s1 "" false 'grep -rn -m 5000 TODO src'
expect deny "echo does not bound the statement before it" s1 "" false 'git log; echo "exit=$?"'
expect deny "git diff alone" s1 "" false 'git diff'
expect deny "ls -R" s1 "" false 'ls -R src'
expect deny "ls with R in a flag cluster" s1 "" false 'ls -laR src'
expect deny "command substitution inside echo" s1 "" false 'echo "$(cat big.log)"'
expect pass "stdout and stderr to /dev/null" s1 "" false 'pnpm build > /dev/null 2>&1'
expect pass "head -n 200" s1 "" false 'git log | head -n 200'
expect pass "tail -c 4000" s1 "" false 'cat a.txt | tail -c 4000'
expect pass "grep -m 20" s1 "" false 'grep -rn -m 20 TODO src'
expect pass "log to a file, then echo the status" s1 "" false 'pnpm test > /tmp/t.log 2>&1; echo "exit=$?"'
expect pass "the same over two lines" s1 "" false 'pnpm test > /tmp/t.log 2>&1
echo "exit=$?"'
expect pass "git status --short" s1 "" false 'git status --short'
expect pass "git diff --stat" s1 "" false 'git diff --stat'
expect pass "git status then git diff --stat" s1 "" false 'git status; git diff --stat'
expect pass "ls without -R" s1 "" false 'ls src'
expect pass "agent-turns, one row per run" s1 "" false 'agent-turns'
expect pass "agent-turns setting a run's limit" s1 "" false 'agent-turns a1484115aae3a905c 720'
expect deny "agent-turns piped into an unbounded command" s1 "" false 'agent-turns | cat'
expect pass "codebase-map dir" s1 "" false 'codebase-map dir'
expect pass "codebase-map status" s1 "" false 'codebase-map status'
expect pass "codebase-map status --oneline" s1 "" false 'codebase-map status --oneline'
expect pass "codebase-map stamp" s1 "" false 'codebase-map stamp'
expect deny "codebase-map modules prints one line per module" s1 "" false 'codebase-map modules'
expect deny "codebase-map modules with a limit" s1 "" false 'codebase-map modules 50'
expect pass "codebase-map modules sent to a file" s1 "" false 'codebase-map modules > /tmp/modules.tsv'
expect deny "codebase-map status piped into an unbounded command" s1 "" false 'codebase-map status | cat'
expect pass "git -C <path> status" s1 "" false 'git -C /abs/repo status --short'
expect deny "git -C <path> log" s1 "" false 'git -C /abs/repo log'
expect pass "grep -m with a | inside single quotes" s1 "" false "grep -n -m 30 -A 15 -E 'FAIL|Error' /abs/t.log"
expect pass "grep -c with a | inside double quotes" s1 "" false 'grep -c "a|b" notes.txt'
expect pass "echo with a ; inside quotes" s1 "" false "echo 'a; b'"
expect deny "a > inside quotes is not a redirect" s1 "" false "git log --format='%h > %s'"
expect deny "a quoted | does not hide the unbounded stage" s1 "" false "git log --grep='a|b'"
expect pass "cut after a capped stage" s1 "" false 'cat notes.txt | head -n 5 | cut -c1-300'
expect pass "cut after grep -m" s1 "" false 'grep -n -m 20 TODO /abs/min.js | cut -c1-300'
expect deny "cut alone" s1 "" false 'cut -c1-300 big.txt'
expect pass "stdout and stderr to two files" s1 "" false 'pnpm build > /tmp/out.log 2> /tmp/err.log'
expect pass "a variable in quotes before other quoted strings" s1 "" false 'mkdir -p "$S/lsp"; { git status --short; echo "=== a"; } > "$S/f.txt" 2>&1; head -c 9000 "$S/f.txt"'
expect deny "quotes pair from the left, so the text between two strings is still read" s1 "" false 'echo "$S/x"; git log --format="%h"'
expect pass "an apostrophe inside double quotes" s1 "" false "echo \"it's done\""
expect deny "an apostrophe inside double quotes, then an unbounded statement" s1 "" false "echo \"it's\"; cat big.log; echo 'x'"
expect pass "an escaped quote inside double quotes" s1 "" false 'printf "%s\n" "a \" b | c" | head -3'

decision() { jq -r '.hookSpecificOutput.permissionDecision // "pass"'; }
state="$CLAUDE_PLUGIN_DATA/agent-orchestration-bash-output"
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}
has_marker() { [ -n "$(ls "$state" 2>/dev/null)" ]; }
check "a deny leaves a marker in the plugin data directory" has_marker

got=$(run "" "" false 'git log --stat' | decision)
[ -n "$got" ] || got=pass
check "no session_id passes" [ "$got" = pass ]
no_none() { [ -z "$(ls "$state" | grep '^none')" ]; }
check "no session_id leaves no marker under a shared name" no_none

fresh="$CLAUDE_PLUGIN_DATA/not-created-yet"
got=$(jq -n '{session_id: "s8", tool_input: {command: "git log --graph"}}' | CLAUDE_PLUGIN_DATA="$fresh" ${HOOK_SH:-sh} "$hook" | decision)
[ -n "$got" ] || got=pass
check "a plugin data directory that does not exist yet is created and used" [ "$got" = deny ]

got=$(run "bad/session" "" false 'git log --stat' | decision)
[ -n "$got" ] || got=pass
check "a session_id with a slash passes" [ "$got" = pass ]

got=$(jq -n '{session_id: "s9", tool_input: {command: "git log --oneline --stat"}}' | env -u CLAUDE_PLUGIN_DATA -u XDG_RUNTIME_DIR -u TMPDIR ${HOOK_SH:-sh} "$hook" | decision)
[ -n "$got" ] || got=pass
check "no marker directory passes" [ "$got" = pass ]

for var in XDG_RUNTIME_DIR TMPDIR; do
  base=$(mktemp -d)
  got=$(jq -n '{session_id: "s7", tool_input: {command: "git log --all"}}' | env -u CLAUDE_PLUGIN_DATA -u XDG_RUNTIME_DIR -u TMPDIR "$var=$base" ${HOOK_SH:-sh} "$hook" | decision)
  landed() { [ "$got" = deny ] && [ -n "$(ls "$base/agent-orchestration-bash-output" 2>/dev/null)" ]; }
  check "without a plugin data directory the marker goes under $var" landed
  rm -rf "$base"
done

rm -rf "$CLAUDE_PLUGIN_DATA"
exit $fail
