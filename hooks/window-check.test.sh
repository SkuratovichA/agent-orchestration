#!/bin/sh
# Cases for window-check.sh. Run: sh hooks/window-check.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/window-check.sh"
shpath=$(command -v sh)
TMPDIR=$(mktemp -d); export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT
fail=0
n=0

# Each case gets its own config dir and working directory.
fresh() { n=$((n + 1)); cfg="$TMPDIR/c$n/cfg"; cwd="$TMPDIR/c$n/cwd"; mkdir -p "$cfg" "$cwd/.claude"; }
run() { # extra env assignment (or empty)
  (cd "$cwd" && jq -n --arg c "$cwd" '{cwd: $c}' | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CONFIG_DIR="$cfg" $1 "$shpath" "$hook"; echo "exit=$?")
}
check() { if [ "$2" = ok ]; then echo "ok    $1"; else echo "FAIL  $1: $2"; fail=1; fi; }
ctx() { printf '%s\n' "$1" | sed '$d' | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }
silent() { # label output
  [ "$2" = "exit=0" ] && r=ok || r="got: $2"; check "$1" "$r"
}
names() { # label output needle
  code=$(printf '%s\n' "$2" | tail -n 1); c=$(ctx "$2")
  case "$c" in *"$3"*) has=1 ;; *) has=0 ;; esac
  [ "$code" = "exit=0" ] && [ "$has" = 1 ] && r=ok || r="got: $2"; check "$1" "$r"
}

fresh; echo '{"modelSettings":{"claude-opus-5-5":{"autoCompactWindow":150000}}}' > "$cfg/settings.json"
out=$(run ""); names "per-model 150000 is named" "$out" "claude-opus-5-5 at 150000 in $cfg/settings.json"

fresh; echo '{"autoCompactWindow":120000}' > "$cfg/settings.json"
out=$(run ""); names "top-level 120000 is named" "$out" "the top-level window at 120000 in $cfg/settings.json"

fresh; echo '{"autoCompactWindow":200000,"modelSettings":{"m":{"autoCompactWindow":300000}}}' > "$cfg/settings.json"
echo '{"autoCompactWindow":"auto"}' > "$cwd/.claude/settings.json"
out=$(run ""); silent "values at or above 200000 and auto: no output" "$out"

fresh
out=$(run ""); silent "no settings file: no output" "$out"

fresh
out=$(run "CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000"); names "environment variable at 150000 is named" "$out" "CLAUDE_CODE_AUTO_COMPACT_WINDOW at 150000"

fresh; echo '{"modelSettings":{"claude-sonnet-5-5":{"autoCompactWindow":100000}}}' > "$cwd/.claude/settings.local.json"
out=$(run ""); names "per-model 100000 in settings.local.json is named with its path" "$out" "claude-sonnet-5-5 at 100000 in $cwd/.claude/settings.local.json"

fresh; echo '{"autoCompactWindow":120000' > "$cfg/settings.json"
out=$(run ""); silent "invalid JSON: no output" "$out"

fresh; echo '{"autoCompactWindow":120000}' > "$cfg/settings.json"; echo '{"autoCompactWindow":150000}' > "$cwd/.claude/settings.json"
out=$(run "CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000"); c=$(ctx "$out")
case "$c" in *"120000 in $cfg/settings.json; the top-level window at 150000 in $cwd/.claude/settings.json; CLAUDE_CODE_AUTO_COMPACT_WINDOW at 100000. About"*) r=ok ;; *) r="got: $c" ;; esac
check "several sources are joined with a semicolon" "$r"

exit $fail
