#!/bin/sh
# SessionEnd: removes the ending session's files in the state directory, which are the Bash-output markers, the session marker, the turn counters and the turn limits (<session>.*), and any file older than a week, which covers sessions that ended without this hook running. The age is a week because a limit file lives as long as its session, and a session can run for days. Silent, and always exits 0.
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
session=$(cat | jq -r '.session_id // ""' 2>/dev/null)
case "$session" in
  ''|*[!A-Za-z0-9_-]*) exit 0 ;;
esac
dir=$(state_dir) || exit 0
rm -f "$dir/$session".* 2>/dev/null
find "$dir" -type f -mtime +6 -exec rm -f {} + 2>/dev/null
exit 0
