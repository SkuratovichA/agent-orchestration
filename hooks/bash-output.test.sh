#!/bin/sh
# Cases for bash-output.sh. Run: sh hooks/bash-output.test.sh
hook="$(cd "$(dirname "$0")" && pwd)/bash-output.sh"
TMPDIR=$(mktemp -d); export TMPDIR
fail=0
run() { # session agent background command
  jq -n --arg s "$1" --arg a "$2" --argjson b "$3" --arg c "$4" '{session_id: $s, hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c, run_in_background: $b}} + (if $a == "" then {} else {agent_id: $a} end)' | sh "$hook"
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
expect deny "stdout sent to stderr" s1 "" false 'echo done >&2'
expect deny "cut bounds the width, not the length" s1 "" false 'grep -rn foo . | cut -c1-200'
expect deny "head in the middle of the pipeline" s1 "" false 'head -5 a.txt | xargs cat'
expect deny "bounded statement followed by an unbounded one" s1 "" false 'git log | head -3; git diff'
expect pass "input without a command" s1 "" false ''
rm -rf "$TMPDIR"
exit $fail
