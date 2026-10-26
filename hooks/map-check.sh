#!/bin/sh
# SessionStart: tell the session that a codebase map of the repository exists and how stale it is. Changes nothing, and exits 0 on every path so it never blocks a session.
command -v jq >/dev/null 2>&1 || exit 0
# The plugin root before the cd below, so a relative $0 still resolves.
root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 0
. "$root/hooks/lib.sh"

# Working directory from the hook's JSON on stdin; $PWD when stdin is empty or not JSON.
cwd=$(hook_cwd)
cd "$cwd" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

line=$(sh "$root/bin/codebase-map" status --oneline 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0

jq -n --arg line "$line" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ($line + " Read its INDEX.md before you plan a change in this repository; the agent-orchestration:mapping-codebases skill says how to read, refresh and build it.")}}' 2>/dev/null
exit 0
