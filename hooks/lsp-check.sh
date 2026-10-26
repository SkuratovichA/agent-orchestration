#!/bin/sh
# SessionStart: say so when the project's language server is not installed. Reads references/language-servers.tsv; installs nothing.
command -v jq >/dev/null 2>&1 || exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
table="$root/references/language-servers.tsv"
[ -r "$table" ] || exit 0

# Working directory from the hook's JSON on stdin; $PWD when stdin is empty or not JSON.
cwd=$(hook_cwd)

# Marker files at the top of the working directory or up to two levels below it, because a workspace root keeps
# its projects one or two levels down. Dependency, build and hidden directories are not searched, and neither is
# anything below the top level of the home directory or of /.
tab=$(printf '\t')
set --
while IFS="$tab" read -r marker rest || [ -n "$marker" ]; do
  case "$marker" in ''|'#'*) continue ;; esac
  [ $# -eq 0 ] || set -- "$@" -o
  set -- "$@" -name "$marker"
done < "$table"
[ $# -gt 0 ] || exit 0
case "$cwd" in /|"$HOME") depth=1 ;; *) depth=3 ;; esac
found=$(find "$cwd/." -maxdepth "$depth" \( -name node_modules -o -name '.?*' -o -name vendor -o -name dist -o -name build -o -name target \) -prune -o -type f \( "$@" \) -print 2>/dev/null | sed 's|.*/||' | sort -u)

# Plugins switched off by name in the user's or the project's settings: a server someone chose not to run is not
# reported as missing. A later file overrides an earlier one, in the order Claude Code reads them.
config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
off=$(cat "$config/settings.json" "$cwd/.claude/settings.json" "$cwd/.claude/settings.local.json" 2>/dev/null | jq -rs 'map(.enabledPlugins // {}) | add // {} | to_entries[] | select(.value == false) | .key | sub("@.*$"; "")' 2>/dev/null)

# One item per row whose marker was found, whose plugin is not switched off and whose binary is off PATH.
items=
while IFS="$tab" read -r marker language plugin binary install || [ -n "$marker" ]; do
  case "$marker" in ''|'#'*) continue ;; esac
  [ -n "$language" ] && [ -n "$plugin" ] && [ -n "$binary" ] && [ -n "$install" ] || continue
  [ -e "$cwd/$marker" ] || printf '%s\n' "$found" | grep -qxF -- "$marker" || continue
  printf '%s\n' "$off" | grep -qxF -- "$plugin" && continue
  command -v "$binary" >/dev/null 2>&1 && continue
  item="$language: install with \`$install\` and enable the \`$plugin\` plugin"
  if [ -n "$items" ]; then items="$items; $item"; else items="$item"; fi
done < "$table"
[ -n "$items" ] || exit 0

jq -n --arg items "$items" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Language server missing for this project; builders use it for navigation and diagnostics. " + $items + ". Tell the user, and install only on their go-ahead.")}}'
