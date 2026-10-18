# Shared by bash-output.sh, turn-budget.sh and cleanup.sh; source it with: . "$(dirname "$0")/lib.sh"

# Prints the private directory that holds the Bash-output markers and the turn counters, creating it when absent. The base is the
# first of CLAUDE_PLUGIN_DATA, XDG_RUNTIME_DIR and TMPDIR that is set and is a directory; the directory must be
# a real one (not a symlink) owned by the current user. Prints nothing and returns 1 when none qualifies.
# CLAUDE_PLUGIN_DATA is the plugin's own directory, so it is created here when it does not exist yet.
state_dir() {
  [ -z "$CLAUDE_PLUGIN_DATA" ] || mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null
  for base in "$CLAUDE_PLUGIN_DATA" "$XDG_RUNTIME_DIR" "$TMPDIR"; do
    [ -n "$base" ] && [ -d "$base" ] || continue
    dir="$base/agent-orchestration-bash-output"
    [ -d "$dir" ] || mkdir -m 700 "$dir" 2>/dev/null
    if [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    return 1
  done
  return 1
}
