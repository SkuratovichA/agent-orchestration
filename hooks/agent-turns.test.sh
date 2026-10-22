#!/bin/sh
# Cases for bin/agent-turns, the command that shows and changes the turn limits of the session's runs, and for its fit with turn-budget.sh and context.sh. Run: sh hooks/agent-turns.test.sh
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
real_root="$(cd "$hooks_dir/.." && pwd)"
# The command and the hooks read and write the state directory of the live plugin, so the test keeps to directories of its own.
tmp=$(mktemp -d)
mkdir "$tmp/config" "$tmp/tmp" "$tmp/data"
CLAUDE_CONFIG_DIR="$tmp/config"; TMPDIR="$tmp/tmp"; CLAUDE_CODE_SESSION_ID=fake-session
export CLAUDE_CONFIG_DIR TMPDIR CLAUDE_CODE_SESSION_ID
unset XDG_RUNTIME_DIR CLAUDE_PLUGIN_DATA
# The plugin's data directory for the hooks: the command is not given it, as the Bash tool does not give it, and finds the state directory under CLAUDE_CONFIG_DIR.
data="$tmp/config/plugins/data/agent-orchestration-test"
state="$data/agent-orchestration-bash-output"
mkdir -p "$data"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}
equal() { [ "$1" = "$2" ]; }

# A fixture plugin root: the command and the hook, two agents with their ceilings, and a table of limits.
root=$(mktemp -d); mkdir "$root/bin" "$root/hooks" "$root/agents" "$root/references"
cp "$real_root/bin/agent-turns" "$root/bin/"; cp "$real_root/hooks/lib.sh" "$real_root/hooks/turn-budget.sh" "$root/hooks/"
printf -- '---\nname: x\nmaxTurns: 100\n---\n\nYou are x.\n' > "$root/agents/x.md"
printf -- '---\nname: y\nmaxTurns: 50\n---\n\nYou are y.\n' > "$root/agents/y.md"
printf '# agent\tturn limit\nx\t8\ny\t4\n' > "$root/references/turn-limits.tsv"
cli="$root/bin/agent-turns"

run_env() { # VAR=value ... as one word; arguments of the command; runs it with those variables set and sets out (stdout), err (stderr) and rc (the exit status)
  assigns=$1; shift
  out=$(env $assigns ${HOOK_SH:-sh} "$cli" "$@" 2> "$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}
run() { run_env "" "$@"; }
fresh() { rm -rf "$state"; mkdir -m 700 "$state"; : > "$state/fake-session.session"; }
row() { printf '%s\n' "$out" | awk -v id="$1" '$1 == id { $1 = $1; print }'; } # the line of an id, with single spaces
file_is() { [ "$(cat "$state/$1" 2>/dev/null)" = "$2" ]; }
no_file() { [ ! -e "$state/$1" ]; }
is_usage() { case "$err" in "agent-turns: "*usage:*) true ;; *) false ;; esac; }
one_line() { [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ]; }
hook_as() { # event agent type [tool]; fires turn-budget.sh of the fixture root for the fake session and prints what it printed
  jq -n --arg e "$1" --arg a "$2" --arg t "$3" --arg l "${4:-Bash}" '{hook_event_name: $e, session_id: "fake-session", agent_id: $a, agent_type: $t, tool_name: $l}' | CLAUDE_PLUGIN_DATA="$data" CLAUDE_PLUGIN_ROOT="$root" ${HOOK_SH:-sh} "$root/hooks/turn-budget.sh"
}

# The listing and the view of one run.
fresh
printf '5 x\n' > "$state/fake-session.turns.a1"
printf '3 y\n' > "$state/fake-session.turns.a2"
printf '2\n' > "$state/fake-session.turns.a3"
printf '1 x\n' > "$state/other-session.turns.a9"
run
check "the listing exits 0" equal "$rc" 0
check "the listing says nothing on stderr" equal "$err" ""
check "the listing has a header line" equal "$(printf '%s\n' "$out" | sed 1q | awk '{ $1 = $1; print }')" "AGENT TYPE ROUNDS LIMIT SOURCE"
check "a run on the table's limit: its type, rounds, limit and source" equal "$(row a1)" "a1 x 5 8 default"
check "a run of another type has that type's limit" equal "$(row a2)" "a2 y 3 4 default"
check "a run with an old counter has no type and so no limit" equal "$(row a3)" "a3 - 2 - -"
check "another session's run is not listed" equal "$(row a9)" ""
check "the listing has the header and three runs" equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 4
aligned() { # the second column starts at one offset on every line
  printf '%s\n' "$out" | awk '{ match($0, /^[^ ]+ +/); print RLENGTH }' | sort -u | wc -l | tr -d ' '
}
check "the columns are aligned" equal "$(aligned)" 1
run a1
check "showing a run exits 0" equal "$rc" 0
check "showing a run prints the header and its line" equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2
check "showing a run prints its line" equal "$(row a1)" "a1 x 5 8 default"
run a3
check "showing a run with an old counter" equal "$(row a3)" "a3 - 2 - -"
run nobody
check "showing an id with no counter exits 0 and shows no rounds and no limit" equal "$(row nobody)" "nobody - 0 - -"
fresh
run
check "a session with no counters lists the header alone" equal "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 1

# Setting and removing the limit of a run.
fresh
printf '5 x\n' > "$state/fake-session.turns.a1"
run a1 20
check "setting the limit of a run exits 0" equal "$rc" 0
check "setting the limit of a run says nothing on stderr" equal "$err" ""
check "setting the limit of a run prints the run's line with the new limit and source run" equal "$(row a1)" "a1 x 5 20 run"
check "the limit is in the file the hook reads" file_is fake-session.limit.a1 20
check "the listing shows it" equal "$(run; row a1)" "a1 x 5 20 run"
run a1 007
check "a limit with leading zeros reads as decimal" equal "$(row a1)" "a1 x 5 7 run"
check "and is stored without them" file_is fake-session.limit.a1 7
run a1 100
check "a limit equal to the ceiling is no cause for a warning" equal "$err" ""
run a1 101
check "a limit above the ceiling exits 0" equal "$rc" 0
check "a limit above the ceiling warns on stderr, in one line" equal "$err" "agent-turns: 101 is above x's maxTurns of 100; Claude Code stops the run there whatever this limit says."
check "a limit above the ceiling is still set" equal "$(row a1)" "a1 x 5 101 run"
run a1 default
check "default exits 0" equal "$rc" 0
check "default removes the limit of the run" no_file fake-session.limit.a1
check "default prints the run's line on the table's limit" equal "$(row a1)" "a1 x 5 8 default"
run a1 default
check "default again is no error" equal "$rc" 0
run fresh1 6
check "a limit can be set for an id that has no counter yet, and shows no type" equal "$(row fresh1)" "fresh1 - 0 6 run"
check "that run has no ceiling to warn about" equal "$err" ""
check "no temporary file is left in the state directory" equal "$(ls "$state" | grep -c '\.[0-9][0-9]*$')" 0

# The limit of an agent type in this session.
fresh
printf '5 x\n' > "$state/fake-session.turns.a1"
printf '3 y\n' > "$state/fake-session.turns.a2"
run --type x
check "showing a type exits 0" equal "$rc" 0
check "showing a type prints the header and the type's line, on the table's limit" equal "$(printf '%s\n' "$out" | awk '{ $1 = $1; print }' | tr '\n' '|')" "TYPE LIMIT SOURCE|x 8 default|"
run --type x 30
check "setting the limit of a type exits 0" equal "$rc" 0
check "setting the limit of a type says nothing on stderr" equal "$err" ""
check "setting the limit of a type prints the effective limit and source session" equal "$(row x)" "x 30 session"
check "the limit of the type is in the file the hook reads" file_is fake-session.typelimit.x 30
run
check "a running run of the type has the limit of the type" equal "$(row a1)" "a1 x 5 30 session"
check "a run of another type does not" equal "$(row a2)" "a2 y 3 4 default"
run a1 9
check "the run's own limit beats the type's" equal "$(row a1)" "a1 x 5 9 run"
run --type x
check "showing the type does not show a run's limit" equal "$(row x)" "x 30 session"
run a1 default
check "removing the run's limit gives the type's back" equal "$(row a1)" "a1 x 5 30 session"
run --type agent-orchestration:x 31
check "the type is accepted with the plugin prefix" equal "$(row x)" "x 31 session"
run --type agent-orchestration:x
check "the type is shown with the plugin prefix" equal "$(row x)" "x 31 session"
check "the prefix makes no second file" file_is fake-session.typelimit.x 31
run --type x 101
check "a limit of the type above the ceiling warns on stderr" equal "$err" "agent-turns: 101 is above x's maxTurns of 100; Claude Code stops the run there whatever this limit says."
check "a limit of the type above the ceiling exits 0 and is set" equal "$rc $(row x)" "0 x 101 session"
run --type x default
check "default exits 0" equal "$rc" 0
check "default removes the limit of the type" no_file fake-session.typelimit.x
check "default prints the table's limit" equal "$(row x)" "x 8 default"
run --type y 2
check "a limit for one type leaves the other alone" equal "$(run --type x; row x)" "x 8 default"

# Refusals.
fresh
run --type nope
check "an unknown type exits 1" equal "$rc" 1
check "an unknown type says so on one line of stderr" one_line
case "$err" in "agent-turns: unknown agent type nope"*) known=1 ;; *) known=0 ;; esac
check "that line begins with the command's name and names the type" equal "$known" 1
run --type nope 5
check "an unknown type is not set" no_file fake-session.typelimit.nope
run --type agent-orchestration:../x 5
check "a type that is no file name exits 1" equal "$rc" 1
run --type other-plugin:x 5
check "a type of another plugin exits 1" equal "$rc" 1
run --type
check "--type with no type exits 2 with the usage" equal "$rc" 2
check "--type with no type prints the usage on stderr" is_usage
run --type x 1 2
check "--type with too many arguments exits 2" equal "$rc" 2
for turns in 0 -3 abc 1.5 '' 1000000000 '5 6'; do
  run a1 "$turns"
  check "turns '$turns' for a run exit 2 with the usage" equal "$rc $(is_usage && echo usage)" "2 usage"
  run --type x "$turns"
  check "turns '$turns' for a type exit 2 with the usage" equal "$rc $(is_usage && echo usage)" "2 usage"
done
check "no refused limit is stored" equal "$(ls "$state" | grep -c -v '^fake-session.session$')" 0
run a1 5 6
check "too many arguments exit 2" equal "$rc" 2
run ../a1 5
check "an id that is no file name exits 2" equal "$rc" 2
check "an id that is no file name writes nothing" equal "$(ls "$state" | grep -c -v '^fake-session.session$')" 0
run -x
check "an unknown option exits 2" equal "$rc" 2
run --help
check "--help exits 0" equal "$rc" 0
check "--help prints the usage on stdout" equal "$(printf '%s\n' "$out" | sed 1q | cut -c1-6)" "usage:"
run -h
check "-h exits 0" equal "$rc" 0
out=$(env -u CLAUDE_CODE_SESSION_ID ${HOOK_SH:-sh} "$cli" --help); rc=$?
check "--help needs no session" equal "$rc" 0
out=$(env -u CLAUDE_CODE_SESSION_ID ${HOOK_SH:-sh} "$cli" 2> "$tmp/err"); rc=$?
check "without CLAUDE_CODE_SESSION_ID the command exits 1" equal "$rc" 1
check "without CLAUDE_CODE_SESSION_ID it says so on one line of stderr" equal "$(wc -l < "$tmp/err" | tr -d ' ') $(cut -c1-13 "$tmp/err")" "1 agent-turns: "
out=$(CLAUDE_CODE_SESSION_ID='../x' ${HOOK_SH:-sh} "$cli" 2> "$tmp/err"); rc=$?
check "with an unsafe session id the command exits 1" equal "$rc" 1
check "with an unsafe session id it says so on one line of stderr" equal "$(wc -l < "$tmp/err" | tr -d ' ') $(cut -c1-13 "$tmp/err")" "1 agent-turns: "

# Where the state directory is found: the first directory that holds the session's marker, failing that the first that holds a file of the session.
lib="agent-orchestration-bash-output"
other="$tmp/config/plugins/data/agent-orchestration-zother/$lib"
fresh
rm -f "$state/fake-session.session"
mkdir -p "$other"; chmod 700 "$other"
printf '1 x\n' > "$state/fake-session.turns.here"
printf '2 x\n' > "$other/fake-session.turns.there"
run
check "with a counter in two directories and no marker the first directory is used" equal "$(row here) $(row there)" "here x 1 8 default "
: > "$other/fake-session.session"
run
check "the directory that holds the marker is used over an earlier one" equal "$(row here) $(row there)" " there x 2 8 default"
rm -f "$other/fake-session.session" "$state/fake-session.session"
run
check "with no marker anywhere a counter is enough to find the directory" equal "$(row here) $(row there)" "here x 1 8 default "
rm -f "$state/fake-session.turns.here"
rm -f "$other/fake-session.turns.there"; : > "$other/fake-session.session"
run
check "a marker alone is enough to find the directory" equal "$rc $(printf '%s\n' "$out" | wc -l | tr -d ' ')" "0 1"
rm -rf "$other"
fresh
run --type x 12
check "a limit set where only the marker was found goes to that directory" file_is fake-session.typelimit.x 12
rm -f "$state/fake-session.typelimit.x"
run_env CLAUDE_CODE_SESSION_ID=another-session
check "a session with no file anywhere exits 1" equal "$rc" 1
check "a session with no file anywhere says so on one line of stderr" one_line
run_env CLAUDE_CODE_SESSION_ID=another-session a1 5
check "a session with no file anywhere does not set a limit" equal "$rc $(ls "$state" | grep -c 'another-session')" "1 0"
# The directory under TMPDIR, the directory the plugin names itself, and the directories the command refuses.
rm -rf "$data"; mkdir -p "$data"
mkdir -m 700 "$TMPDIR/$lib"; : > "$TMPDIR/$lib/fake-session.session"; printf '4 y\n' > "$TMPDIR/$lib/fake-session.turns.tmp1"
run
check "a directory under TMPDIR is found" equal "$(row tmp1)" "tmp1 y 4 4 default"
mkdir -m 700 "$tmp/runtime" "$tmp/runtime/$lib"; : > "$tmp/runtime/$lib/fake-session.session"; printf '4 x\n' > "$tmp/runtime/$lib/fake-session.turns.run1"
run_env XDG_RUNTIME_DIR="$tmp/runtime"
check "a directory under XDG_RUNTIME_DIR comes before TMPDIR's" equal "$(row tmp1) $(row run1)" " run1 x 4 8 default"
mkdir -p "$tmp/plugin-data/$lib"; chmod 700 "$tmp/plugin-data/$lib"; : > "$tmp/plugin-data/$lib/fake-session.session"; printf '6 y\n' > "$tmp/plugin-data/$lib/fake-session.turns.pd1"
run_env "CLAUDE_PLUGIN_DATA=$tmp/plugin-data XDG_RUNTIME_DIR=$tmp/runtime"
check "CLAUDE_PLUGIN_DATA, when set, comes first" equal "$(row pd1) $(row run1) $(row tmp1)" "pd1 y 6 4 default  "
rm -rf "$tmp/plugin-data" "$tmp/runtime" "$TMPDIR/$lib"
mkdir -p "$tmp/real/$lib"; : > "$tmp/real/$lib/fake-session.session"; chmod 700 "$tmp/real/$lib"
mkdir -p "$data"; ln -s "$tmp/real/$lib" "$data/$lib"
run
check "a state directory that is a symlink is refused" equal "$rc" 1
rm -rf "$data" "$tmp/real"; mkdir -p "$data"

# The command and the hooks together. The Bash tool gives the command no CLAUDE_PLUGIN_DATA, so it finds the directory by the marker context.sh writes at the start of the session.
printf '{"session_id":"fake-session","source":"startup"}' | CLAUDE_PLUGIN_ROOT="$real_root" CLAUDE_PLUGIN_DATA="$data" ${HOOK_SH:-sh} "$real_root/hooks/context.sh" SessionStart > /dev/null
check "the SessionStart hook leaves the session marker in the plugin's state directory" [ -e "$state/fake-session.session" ]
run
check "the marker is how the command finds the directory: an empty listing" equal "$rc $(printf '%s\n' "$out" | wc -l | tr -d ' ')" "0 1"
real_cli="$real_root/bin/agent-turns"
out=$(${HOOK_SH:-sh} "$real_cli" --type reader)
check "the shipped command shows the shipped limit of the reader" equal "$(printf '%s\n' "$out" | awk '$1 == "reader" { $1 = $1; print }')" "reader 60 default"
out=$(${HOOK_SH:-sh} "$real_cli" --type agent-orchestration:builder-m)
check "and of builder-m, with the prefix" equal "$(printf '%s\n' "$out" | awk '$1 == "builder-m" { $1 = $1; print }')" "builder-m 360 default"
i=0
while [ "$i" -lt 8 ]; do hook_as PostToolBatch e1 agent-orchestration:x > /dev/null; i=$((i + 1)); done
run e1
check "the hook's counter is what the command lists" equal "$(row e1)" "e1 x 8 8 default"
deny=$(hook_as PreToolUse e1 agent-orchestration:x)
check "a run at its limit of 8 is refused" equal "$(printf '%s' "$deny" | jq -r '.hookSpecificOutput.permissionDecision')" deny
run e1 12
check "raising its limit exits 0" equal "$rc" 0
check "raising its limit shows 12 for the run" equal "$(row e1)" "e1 x 8 12 run"
check "the next call of the run goes through" equal "$(hook_as PreToolUse e1 agent-orchestration:x)" ""
run e1 3
check "lowering the limit below the rounds refuses the next call" equal "$(hook_as PreToolUse e1 agent-orchestration:x | jq -r '.hookSpecificOutput.permissionDecision')" deny
run e1 default
check "default puts the table's limit back: refused at 8 of 8" equal "$(hook_as PreToolUse e1 agent-orchestration:x | jq -r '.hookSpecificOutput.permissionDecision')" deny
run --type x 10
check "a limit of the type lets the run through" equal "$(hook_as PreToolUse e1 agent-orchestration:x)" ""
i=0
while [ "$i" -lt 10 ]; do hook_as PostToolBatch e2 agent-orchestration:x > /dev/null; i=$((i + 1)); done
reason=$(hook_as PreToolUse e2 agent-orchestration:x | jq -r '.hookSpecificOutput.permissionDecisionReason')
case "$reason" in *"has made 10 tool rounds and its turn limit is 10,"*) refused=1 ;; *) refused=0 ;; esac
check "and a run of the type that starts later is bound by it: 10 rounds, then refused" equal "$refused" 1

rm -rf "$tmp" "$root"
exit $fail
