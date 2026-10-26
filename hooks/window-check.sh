#!/bin/sh
# SessionStart: name every compaction window below the floor that the session can pick up. Changes nothing.
floor=200000
command -v jq >/dev/null 2>&1 || exit 0
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# Working directory from the hook's JSON on stdin; $PWD when stdin is empty or not JSON.
cwd=$(hook_cwd)

items=
add() {
  if [ -n "$items" ]; then items="$items; $1"; else items="$1"; fi
}

# One item per number below the floor: the top-level window and each modelSettings entry.
for file in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$cwd/.claude/settings.json" "$cwd/.claude/settings.local.json"; do
  [ -r "$file" ] || continue
  found=$(jq -r --argjson floor "$floor" '
    [ (.autoCompactWindow | select(type == "number" and . < $floor) | "the top-level window at \(.)"),
      ((.modelSettings // {}) | if type == "object" then to_entries[] else empty end
        | select(.value | type == "object")
        | .key as $model | .value.autoCompactWindow | select(type == "number" and . < $floor)
        | "\($model) at \(.)") ] | .[]' "$file" 2>/dev/null) || continue
  [ -n "$found" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] && add "$line in $file"
  done <<EOT
$found
EOT
done

env_window="$CLAUDE_CODE_AUTO_COMPACT_WINDOW"
case "$env_window" in
  ''|*[!0-9]*) ;;
  *) [ "$env_window" -lt "$floor" ] && add "CLAUDE_CODE_AUTO_COMPACT_WINDOW at $env_window" ;;
esac
[ -n "$items" ] || exit 0

jq -n --arg items "$items" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Compaction window below 200K tokens: " + $items + ". About 100K tokens of system prompt, tools, CLAUDE.md, memory and loaded skills come back after every compaction, so a window this small compacts again within a few requests and can thrash. Tell the user, and change it, with /autocompact or in the file named, only on their go-ahead.")}}'
exit 0
