#!/bin/sh
# Cases for context.sh and the hook wiring in hooks.json. Run: sh hooks/context.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/context.sh"
block="$root/skills/agent-orchestration/references/worker-brief-block.md"
shell="${HOOK_SH:-sh}"
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

bin=$(mktemp -d)
for tool in cat sed awk dirname; do ln -s "$(command -v $tool)" "$bin/$tool"; done
shell_path=$(command -v "$shell")
out=$(printf '%s' '{"agent_type":"agent-orchestration:builder-m"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SubagentStart); rc=$?
got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
if [ "$rc" = 0 ] && [ "$got" = "$(cat "$block")" ]; then ok "builder emits without jq on PATH"; else bad "builder emits without jq on PATH" "exit $rc"; fi
out=$(printf '%s' '{"agent_type":"Explore"}' | PATH=$bin CLAUDE_PLUGIN_ROOT=$root "$shell_path" "$hook" SubagentStart); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "other type is silent without jq on PATH"; else bad "other type is silent without jq on PATH" "exit $rc"; fi
rm -rf "$bin"

ROOT=$(mktemp -d)
out=$(sub agent-orchestration:builder-m); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "no block file, no output"; else bad "no block file, no output" "exit $rc"; fi
rm -rf "$ROOT"; unset ROOT

pin() { # label jq filter
  if jq -e "$2" "$root/hooks/hooks.json" >/dev/null 2>&1; then ok "$1"; else bad "$1" "hooks.json does not satisfy $2"; fi
}
pin "SubagentStart matcher names the builder types" '.hooks.SubagentStart[0].matcher == "^agent-orchestration:builder-"'
pin "SessionStart matcher of context.sh includes resume" '[.hooks.SessionStart[] | select(any(.hooks[]; .command | contains("context.sh"))) | .matcher] | any(contains("resume"))'
pin "SessionEnd runs cleanup.sh" '[.hooks.SessionEnd[].hooks[].command] | any(contains("cleanup.sh"))'
exit $fail
