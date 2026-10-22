# Shared by bash-output.sh, turn-budget.sh, context.sh, cleanup.sh and bin/agent-turns; source it with: . "$(dirname "$0")/lib.sh"

# Prints the private directory that holds the Bash-output markers, the session markers, the turn counters and the turn limits, creating it when absent. The base is the
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

# Succeeds when $1 is a positive integer of at most nine digits and leaves it without leading zeros in $int, so that it is safe in arithmetic (a leading zero makes the shell read octal). Returns 1 for anything else.
positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  int=${1#"${1%%[!0]*}"}
  [ -n "$int" ] && [ "${#int}" -le 9 ]
}

# Prints the maxTurns of <root>/agents/<name>.md, the hard ceiling that Claude Code enforces: the maxTurns line between the first two "---" lines of the file, with spaces around the number tolerated. Returns 1, printing nothing, when the file or the line is missing or the value is no positive integer. Call it in a command substitution: it sets variables of its own.
max_turns() {
  file="$1/agents/$2.md"
  [ -r "$file" ] || return 1
  blank=" $(printf '\t')"
  marks=0
  while IFS= read -r line; do
    case "$line" in
      ---*) marks=$((marks + 1)); [ "$marks" -lt 2 ] || return 1 ;;
      maxTurns:*)
        [ "$marks" -eq 1 ] || continue
        value=${line#maxTurns:}
        value=${value#"${value%%[!$blank]*}"}
        value=${value%%[$blank]*}
        if positive_int "$value"; then printf '%s\n' "$int"; return 0; fi
        return 1
        ;;
    esac
  done < "$file"
  return 1
}

# Prints "<limit> <source>", the turn limit of one subagent run: the first positive integer found, in order, in <dir>/<session>.limit.<agent> (source "run": set for this run), <dir>/<session>.typelimit.<name> (source "session": set for the agent type in this session) and the <name> row of <root>/references/turn-limits.tsv (source "default"). An empty <agent> skips the first, an empty <name> the last two. Returns 1, printing nothing, when none applies; the run then has no limit from this plugin and only its maxTurns bounds it. The files are read on every call, so a change is seen on the run's next tool call. Call it in a command substitution: it sets variables of its own.
turn_limit() {
  if [ -n "$4" ] && [ -r "$2/$3.limit.$4" ]; then
    read -r value _ < "$2/$3.limit.$4"
    if positive_int "$value"; then printf '%s run\n' "$int"; return 0; fi
  fi
  [ -n "$5" ] || return 1
  if [ -r "$2/$3.typelimit.$5" ]; then
    read -r value _ < "$2/$3.typelimit.$5"
    if positive_int "$value"; then printf '%s session\n' "$int"; return 0; fi
  fi
  if [ -r "$1/references/turn-limits.tsv" ]; then
    tab=$(printf '\t')
    while IFS=$tab read -r row value _ || [ -n "$row" ]; do
      [ "$row" = "$5" ] || continue
      if positive_int "$value"; then printf '%s default\n' "$int"; return 0; fi
      break
    done < "$1/references/turn-limits.tsv"
  fi
  return 1
}
