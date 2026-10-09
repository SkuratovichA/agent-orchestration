#!/bin/sh
# SessionStart: say so when the project's language server is not installed. Reads references/language-servers.tsv; installs nothing.
command -v jq >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
table="$root/references/language-servers.tsv"
[ -r "$table" ] || exit 0

# Working directory from the hook's JSON on stdin; $PWD when stdin is empty or not JSON.
cwd=$(jq -r '.cwd | select(type == "string")' 2>/dev/null) || cwd=
[ -n "$cwd" ] || cwd="$PWD"

# One item per row whose marker sits at the top of the working directory and whose binary is off PATH.
tab=$(printf '\t')
items=
while IFS="$tab" read -r marker language plugin binary install || [ -n "$marker" ]; do
  case "$marker" in ''|'#'*) continue ;; esac
  [ -n "$language" ] && [ -n "$plugin" ] && [ -n "$binary" ] && [ -n "$install" ] || continue
  [ -e "$cwd/$marker" ] || continue
  command -v "$binary" >/dev/null 2>&1 && continue
  item="$language: install with \`$install\` and enable the \`$plugin\` plugin"
  if [ -n "$items" ]; then items="$items; $item"; else items="$item"; fi
done < "$table"
[ -n "$items" ] || exit 0

jq -n --arg items "$items" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Language server missing for this project; builders use it for navigation and diagnostics. " + $items + " Tell the user, and install only on their go-ahead.")}}'
