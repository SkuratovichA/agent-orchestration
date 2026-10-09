#!/bin/sh
event="$1"
command -v jq >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
block="$root/references/worker-brief-block.md"
[ -r "$block" ] || exit 0

case "$event" in
  SessionStart)
    jq -n --arg e "$event" '{hookSpecificOutput: {hookEventName: $e, additionalContext: "The agent-orchestration plugin is active. Its SubagentStart hook puts references/worker-brief-block.md into the context of every subagent this session spawns, so a brief does not paste that block. Load the agent-orchestration skill before spawning anything, and agent-orchestration:writing-briefs before writing the prompt for any agent or Workflow stage."}}'
    ;;
  SubagentStart)
    jq -Rs --arg e "$event" '{hookSpecificOutput: {hookEventName: $e, additionalContext: ("Injected by the agent-orchestration plugin. It binds you whether or not your brief repeats it.\n\n" + .)}}' "$block"
    ;;
esac
