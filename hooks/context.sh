#!/bin/sh
# SessionStart: points the session at the plugin's skills. SubagentStart: puts the worker rules block into the
# context of the plugin's builder types, which have the shell and the Agent tool the block is about. The reader
# and the reviewers work from their own definitions, and any other agent type (Explore, Plan, another plugin's
# agents) gets nothing. The JSON is built with awk, so a missing jq loses nothing.
event="$1"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
block="$root/skills/agent-orchestration/references/worker-brief-block.md"
[ -r "$block" ] || exit 0

case "$event" in
  SessionStart)
    input=$(cat)
    if command -v jq >/dev/null 2>&1; then
      source=$(printf '%s' "$input" | jq -r '.source | select(type == "string")' 2>/dev/null)
    else
      source=$(printf '%s\n' "$input" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 1q)
    fi
    # The empty marker <session>.session tells bin/agent-turns which state directory holds this session's files; the Bash tool does not see CLAUDE_PLUGIN_DATA. Writing it again on resume, clear and compact keeps its age fresh.
    if command -v jq >/dev/null 2>&1; then
      session=$(printf '%s' "$input" | jq -r '.session_id | select(type == "string")' 2>/dev/null)
    else
      session=$(printf '%s\n' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 1q)
    fi
    case "$session" in
      ''|*[!A-Za-z0-9_-]*) ;;
      *)
        . "$(dirname "$0")/lib.sh"
        if dir=$(state_dir 2>/dev/null); then printf '' 2>/dev/null > "$dir/$session.session"; fi
        ;;
    esac
    if [ "$source" = compact ]; then
      printf '%s\n' 'The agent-orchestration skills you loaded before this compaction are re-attached in this context, so do not load them again, and re-read one of their references only for a section you need now and do not have. If you had not loaded them, load agent-orchestration:agent-orchestration before spawning a subagent or a Workflow stage, and agent-orchestration:writing-briefs before writing a brief.'
      exit 0
    fi
    printf '%s\n' 'The agent-orchestration plugin is active. Load its agent-orchestration:agent-orchestration skill before spawning a subagent or a Workflow stage, and agent-orchestration:writing-briefs before writing a brief. Its builder types receive the plugin'"'"'s worker rules on their own; any other implementer you want bound by them gets worker-brief-block.md pasted into its brief.'
    ;;
  SubagentStart)
    input=$(cat)
    if command -v jq >/dev/null 2>&1; then
      type=$(printf '%s' "$input" | jq -r '.agent_type // ""' 2>/dev/null)
    else
      type=$(printf '%s\n' "$input" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 1q)
    fi
    case "$type" in
      ''|agent-orchestration:builder-*) ;;
      *) exit 0 ;;
    esac
    printf '%s' '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"'
    awk '{
      out = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "\\") c = "\\\\"
        else if (c == "\"") c = "\\\""
        else if (c == "\t") c = "\\t"
        else if (c == "\r") c = "\\r"
        out = out c
      }
      printf "%s%s", out, "\\n"
    }' "$block"
    printf '%s\n' '"}}'
    ;;
esac
exit 0
