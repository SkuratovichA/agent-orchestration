#!/bin/sh
# PreToolUse on Bash, for the main conversation only: whatever a command prints there is re-read on every
# later request. A command whose text does not bound its own output is refused once, with the ways to bound
# it; the same command sent again runs. The text bounds its output when it ends in a cap (wc, grep -c, -q or
# -m, head or tail with a small count; a cut may follow) or in a redirect to a file. Trailing statements that print next to
# nothing (echo, cd, git status, ls without -R) are set aside first. A subagent's Bash passes untouched,
# because reading whole output and returning the facts is what a subagent is for. The markers live in a
# private directory (lib.sh); without a safe session id or marker directory the hook lets the call through.
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
set -f
input=$(cat)
IFS='|' read -r agent background <<EOF
$(printf '%s' "$input" | jq -r '"\(.agent_id // "")|\(.tool_input.run_in_background // false)"')
EOF
[ -n "$agent" ] && exit 0
[ "$background" = true ] && exit 0
session=$(printf '%s' "$input" | jq -r '.session_id // ""')
case "$session" in
  ''|*[!A-Za-z0-9_-]*) exit 0 ;;
esac
dir=$(state_dir) || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' | tr '\n\t' '; ')

# A count is a plain number no larger than the limit; "+5", "-5" and the empty string are not.
count_le() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -le "$2" ] 2>/dev/null
}

# One pipeline stage that caps its output. Following output (tail -f) and counts that skip lines from the
# start (tail -n +2, head -n -2) cap nothing.
capped() {
  set -- $1
  case "$1" in
    wc) return 0 ;;
    grep)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --) break ;;
          -m) count_le "$2" 200 && return 0 ;;
          -m[0-9]*) count_le "${1#-m}" 200 && return 0 ;;
          --max-count=*) count_le "${1#*=}" 200 && return 0 ;;
          -[!-]*) case "$1" in *[cq]*) return 0 ;; esac ;;
        esac
        shift
      done
      return 1
      ;;
    head|tail)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in
          --follow*|-f|-F|-[!-]*[fF]*) return 1 ;;
          +[0-9]*) return 1 ;;
          -n) count_le "$2" 200 || return 1; shift ;;
          -n*) count_le "${1#-n}" 200 || return 1 ;;
          --lines=*) count_le "${1#*=}" 200 || return 1 ;;
          -c) count_le "$2" 20000 || return 1; shift ;;
          -c*) count_le "${1#-c}" 20000 || return 1 ;;
          --bytes=*) count_le "${1#*=}" 20000 || return 1 ;;
          -[0-9]*) count_le "${1#-}" 200 || return 1 ;;
        esac
        shift
      done
      return 0
      ;;
  esac
  return 1
}

# The text ends in a redirect of stdout to a file, with or without a redirect of stderr after it; /dev/stderr,
# /dev/stdout, /dev/tty and /dev/fd/N are not files.
file_redirect() {
  target=$(printf ' %s' "$1" | sed -nE 's/.*(([^2&>]>>?)|(&>>?))[[:space:]]*([^[:space:]&|;<>]+)([[:space:]]+2>(&1|>?[[:space:]]*[^[:space:]&|;<>]+))?$/\4/p')
  case "$target" in
    ''|/dev/stderr|/dev/stdout|/dev/tty|/dev/fd/*) return 1 ;;
  esac
  return 0
}

# One statement that prints next to nothing.
quiet() {
  case "$1" in *'|'*|*'$('*|*'`'*) return 1 ;; esac
  set -- $1
  case "$1" in
    echo|printf|true|:|pwd|cd|test|'['|mkdir|touch|wc|agent-turns) return 0 ;;
    codebase-map) [ "$2" != modules ]; return ;;
    git)
      shift
      while [ "$1" = -C ] && [ $# -ge 2 ]; do shift 2; done
      case "$1" in
        status|add|rev-parse) return 0 ;;
        branch) [ "$2" = --show-current ]; return ;;
        diff) case " $* " in *' --stat '*|*' --shortstat '*|*' --name-only '*|*' --quiet '*) return 0 ;; esac ;;
      esac
      return 1
      ;;
    ls)
      for arg; do
        case "$arg" in --recursive|-R|-[!-]*R*) return 1 ;; esac
      done
      return 0
      ;;
  esac
  return 1
}

# The pipeline stage that decides the length: a trailing cut only narrows the lines, so the stage before it counts.
deciding_stage() {
  rest=$1
  while :; do
    stage=${rest##*'|'}
    set -- $stage
    [ "$1" = cut ] && [ "$rest" != "$stage" ] || break
    rest=${rest%'|'*}
  done
  printf '%s' "$stage"
}

# The last statement: the text after the last ; && or ||. Without a separator it is the whole text.
last_statement() {
  printf '%s' "$1" | sed -E 's/.*(;|&&|\|\|)//'
}

# Quoted text is replaced by a placeholder first, so a | ; or > inside quotes is not read as shell syntax. Quotes
# are paired from the left, one string at a time. A double-quoted string that holds a command substitution
# becomes $(Q), because what it prints is not known; any other string becomes Q.
text=$(printf '%s' "$command" | awk '{
  out = ""
  n = length($0)
  i = 1
  while (i <= n) {
    c = substr($0, i, 1)
    if (c == "\\") { out = out substr($0, i, 2); i += 2; continue }
    if (c == "\047") {
      j = index(substr($0, i + 1), "\047")
      if (j == 0) { out = out substr($0, i); break }
      out = out "Q"; i += j + 1; continue
    }
    if (c == "\"") {
      j = i + 1
      while (j <= n && substr($0, j, 1) != "\"") j += (substr($0, j, 1) == "\\") ? 2 : 1
      if (j > n) { out = out substr($0, i); break }
      s = substr($0, i, j - i + 1)
      out = out ((index(s, "$(") > 0 || index(s, "`") > 0) ? "$(Q)" : "Q")
      i = j + 1; continue
    }
    out = out c; i++
  }
  printf "%s", out
}')

# Looked at from the end: an empty text, a cap or a file at the end passes; a quiet last statement is dropped
# with its separator and the rest is looked at again; anything else is refused. Here-documents are not parsed,
# since a wrong refusal costs one resend.
while :; do
  text=$(printf '%s' "$text" | sed -E 's/^([[:space:]]|;)+//; s/([[:space:];]|&&|\|\|)+$//')
  [ -n "$text" ] || exit 0
  last=$(last_statement "$text")
  capped "$(deciding_stage "$last")" && exit 0
  file_redirect "$text" && exit 0
  quiet "$last" || break
  text=${text%"$last"}
done

# Asked once per distinct command and session. If the mark cannot be written the hook lets the call through,
# because a refusal that can never be answered would block the command for good.
mark="$dir/$session.$(printf '%s' "$command" | cksum | tr -cd '0-9')"
[ -f "$mark" ] && exit 0
: > "$mark" 2>/dev/null || exit 0
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "Nothing in this command bounds its output, and what it prints stays in the main conversation and is re-read on every later request. Bound it and run that instead: send stdout to a file and read the part you need, or end the pipeline in head, tail -c 4000, wc, grep -c or grep -m 20. If the output is large and needs judging, give the goal and the command to an agent-orchestration:reader. If you are certain it prints only a few lines, send the same command again unchanged and it will run."}}'
