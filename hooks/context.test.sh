#!/bin/sh
# Cases for context.sh and the hook wiring in hooks.json. Run: sh hooks/context.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/context.sh"
block="$root/skills/agent-orchestration/references/worker-brief-block.md"
shell="${HOOK_SH:-sh}"
# SessionStart writes a marker into the plugin's state directory, which the live plugin also uses, so the test keeps to directories of its own.
tmp=$(mktemp -d)
mkdir "$tmp/data" "$tmp/config" "$tmp/tmp"
CLAUDE_PLUGIN_DATA="$tmp/data"; CLAUDE_CONFIG_DIR="$tmp/config"; TMPDIR="$tmp/tmp"; CLAUDE_CODE_SESSION_ID=fake-session
export CLAUDE_PLUGIN_DATA CLAUDE_CONFIG_DIR TMPDIR CLAUDE_CODE_SESSION_ID
unset XDG_RUNTIME_DIR
state="$CLAUDE_PLUGIN_DATA/agent-orchestration-bash-output"
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1: $2"; fail=1; }
sub() { # agent_type; empty means an input without agent_type
  if [ -n "$1" ]; then input=$(jq -nc --arg t "$1" '{agent_type: $t, agent_id: "a1"}'); else input='{"agent_id":"a1"}'; fi
  printf '%s' "$input" | CLAUDE_PLUGIN_ROOT="${ROOT:-$root}" "${SHELL_BIN:-$shell}" "$hook" SubagentStart
}
emits() { # label agent_type
  out=$(sub "$2"); rc=$?
  want=$(cat "$block")
  got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
  event=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
  if [ "$rc" != 0 ]; then bad "$1" "exit $rc"
  elif [ "$event" != SubagentStart ]; then bad "$1" "no valid SubagentStart JSON"
  elif [ "$got" != "$want" ]; then bad "$1" "additionalContext differs from the block file"
  else ok "$1"; fi
}
silent() { # agent_type
  out=$(sub "$1"); rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "no output for $1"; else bad "no output for $1" "exit $rc, output: $(printf '%s' "$out" | head -c 80)"; fi
}

emits "plugin builder-m" agent-orchestration:builder-m
emits "plugin builder-l" agent-orchestration:builder-l
emits "input without agent_type" ""
for t in agent-orchestration:reader agent-orchestration:reviewer agent-orchestration:reviewer-arch Explore Plan general-purpose statusline-setup claude-code-guide other-plugin:builder-m my-agent-orchestration:builder-m; do silent "$t"; done

out=$(CLAUDE_PLUGIN_ROOT=$root "$shell" "$hook" SessionStart </dev/null); rc=$?
case "$out" in
  *agent-orchestration:agent-orchestration*agent-orchestration:writing-briefs*) [ "$rc" = 0 ] && ok "SessionStart names both skills" || bad "SessionStart names both skills" "exit $rc" ;;
  *) bad "SessionStart names both skills" "output: $(printf '%s' "$out" | head -c 80)" ;;
esac

sess() { # source json; runs SessionStart with that stdin
  printf '%s' "$1" | CLAUDE_PLUGIN_ROOT=$root "${2:-$shell}" "$hook" SessionStart
}
has() { # label output needle expect(1|0)
  case "$2" in *"$3"*) found=1 ;; *) found=0 ;; esac
  if [ "$found" = "$4" ]; then ok "$1"; else bad "$1" "output: $(printf '%s' "$2" | head -c 80)"; fi
}
out=$(sess '{"source":"compact"}'); has "compact source says re-attached" "$out" "re-attached" 1; has "compact source drops the startup line" "$out" "The agent-orchestration plugin is active" 0
out=$(sess '{"source":"startup"}'); has "startup source prints the startup line" "$out" "The agent-orchestration plugin is active" 1; has "startup source does not say re-attached" "$out" "re-attached" 0
out=$(sess ''); has "empty stdin prints the startup line" "$out" "The agent-orchestration plugin is active" 1; has "empty stdin does not say re-attached" "$out" "re-attached" 0
out=$(sess 'not json'); has "non-JSON stdin prints the startup line" "$out" "The agent-orchestration plugin is active" 1

bin=$(mktemp -d)
for tool in cat sed awk dirname mkdir; do ln -s "$(command -v $tool)" "$bin/$tool"; done
shell_path=$(command -v "$shell")
out=$(printf '%s' '{"agent_type":"agent-orchestration:builder-m"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SubagentStart); rc=$?
got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if [ "$rc" = 0 ] && [ "$got" = "$(cat "$block")" ]; then ok "builder emits without jq on PATH"; else bad "builder emits without jq on PATH" "exit $rc"; fi
out=$(printf '%s' '{"agent_type":"Explore"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SubagentStart); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "other type is silent without jq on PATH"; else bad "other type is silent without jq on PATH" "exit $rc"; fi
out=$(printf '%s' '{"source":"compact"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SessionStart); has "compact source says re-attached without jq on PATH" "$out" "re-attached" 1
out=$(printf '%s' '{"source":"startup"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SessionStart); has "startup source says no re-attached without jq on PATH" "$out" "re-attached" 0
out=$(printf '%s' '{"session_id":"nojq-1","source":"startup"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SessionStart); rc=$?
if [ "$rc" = 0 ] && [ -e "$state/nojq-1.session" ]; then ok "the session marker is written without jq on PATH"; else bad "the session marker is written without jq on PATH" "exit $rc"; fi
rm -rf "$bin"

ROOT=$(mktemp -d)
out=$(sub agent-orchestration:builder-m); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "no block file, no output"; else bad "no block file, no output" "exit $rc"; fi
rm -rf "$ROOT"; unset ROOT

# The session marker, which bin/agent-turns uses to find the state directory.
marked() { # label json source-word; the SessionStart for that input leaves the marker, an empty file, and prints what it printed before
  rm -rf "$state"
  out=$(sess "$2"); rc=$?
  if [ "$rc" = 0 ] && [ -e "$state/$3.session" ] && [ ! -s "$state/$3.session" ]; then ok "$1"; else bad "$1" "exit $rc, files: $(ls "$state" 2>&1 | head -c 80)"; fi
}
marked "startup leaves the session marker" '{"session_id":"sess-1","source":"startup"}' sess-1
case "$out" in *"The agent-orchestration plugin is active"*) ok "startup still prints the startup line" ;; *) bad "startup still prints the startup line" "output: $(printf '%s' "$out" | head -c 80)" ;; esac
marked "resume leaves the session marker" '{"session_id":"sess-2","source":"resume"}' sess-2
marked "clear leaves the session marker" '{"session_id":"sess-3","source":"clear"}' sess-3
marked "compact leaves the session marker" '{"session_id":"sess-4","source":"compact"}' sess-4
case "$out" in *"re-attached"*) ok "compact still prints its line" ;; *) bad "compact still prints its line" "output: $(printf '%s' "$out" | head -c 80)" ;; esac
marked "a source-less input leaves the session marker" '{"session_id":"sess-5"}' sess-5
nothing_written() { # label json; the SessionStart for that input writes no file and exits 0
  rm -rf "$state"
  out=$(sess "$2"); rc=$?
  if [ "$rc" = 0 ] && { [ ! -d "$state" ] || [ -z "$(ls "$state")" ]; }; then ok "$1"; else bad "$1" "exit $rc, files: $(ls "$state" 2>&1 | head -c 80)"; fi
}
nothing_written "no session_id writes no marker" '{"source":"startup"}'
nothing_written "an empty input writes no marker" ''
nothing_written "an input that is no JSON writes no marker" 'not json'
nothing_written "a session_id that is no string writes no marker" '{"session_id":12,"source":"startup"}'
nothing_written "a session_id with a path in it writes no marker" '{"session_id":"../escape","source":"startup"}'
nothing_written "a session_id with a slash writes no marker" '{"session_id":"a/b","source":"startup"}'
if [ ! -e "$tmp/escape.session" ] && [ ! -e "$tmp/data/escape.session" ]; then ok "and nothing outside the state directory"; else bad "and nothing outside the state directory" "a file named escape.session exists"; fi
rm -rf "$state"; : > "$state"
out=$(sess '{"session_id":"sess-6","source":"startup"}'); rc=$?
case "$out" in *"The agent-orchestration plugin is active"*) active=1 ;; *) active=0 ;; esac
if [ "$rc" = 0 ] && [ "$active" = 1 ]; then ok "a state directory that cannot be made leaves no marker, and the line is printed all the same"; else bad "a state directory that cannot be made leaves no marker, and the line is printed all the same" "exit $rc"; fi
rm -f "$state"

pin() { # label jq filter
  if jq -e "$2" "$root/hooks/hooks.json" >/dev/null 2>&1; then ok "$1"; else bad "$1" "hooks.json does not satisfy $2"; fi
}
pin "SubagentStart matcher names the builder types" '.hooks.SubagentStart[0].matcher == "^agent-orchestration:builder-"'
pin "SessionStart matcher of context.sh includes resume" '[.hooks.SessionStart[] | select(any(.hooks[]; .command | contains("context.sh"))) | .matcher] | any(contains("resume"))'
pin "SessionEnd runs cleanup.sh" '[.hooks.SessionEnd[].hooks[].command] | any(contains("cleanup.sh"))'
pin "PreToolUse runs turn-budget.sh for every tool" '[.hooks.PreToolUse[] | select(.matcher == null) | .hooks[].command] | any(contains("turn-budget.sh"))'
pin "PreToolUse still runs bash-output.sh for Bash" '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].command] | any(contains("bash-output.sh"))'
pin "PostToolBatch runs turn-budget.sh" '[.hooks.PostToolBatch[].hooks[].command] | any(contains("turn-budget.sh"))'
rm -rf "$tmp"
exit $fail
