#!/bin/sh
# Cases for lsp-check.sh. Run: sh hooks/lsp-check.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/hooks/lsp-check.sh"
shpath=$(command -v sh)
TMPDIR=$(mktemp -d); export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT
fail=0

# PATH holding only the tools the script needs, so a server installed on this machine cannot leak in.
bare="$TMPDIR/bare"; mkdir "$bare"
for tool in sh jq cat grep cut sed tr dirname; do
  p=$(command -v "$tool") && [ -x "$p" ] && ln -s "$p" "$bare/$tool"
done

# A stub server found first on PATH.
stubs="$TMPDIR/stubs"; mkdir "$stubs"
printf '#!/bin/sh\nexit 0\n' > "$stubs/typescript-language-server"; chmod +x "$stubs/typescript-language-server"

mkdir "$TMPDIR/empty" "$TMPDIR/ts" "$TMPDIR/both"
touch "$TMPDIR/ts/tsconfig.json" "$TMPDIR/both/tsconfig.json" "$TMPDIR/both/pyproject.toml"

run() { # path stdin cwd-to-run-in
  (cd "$3" && printf '%s' "$2" | env PATH="$1" CLAUDE_PLUGIN_ROOT="$root" "$shpath" "$hook"; echo "exit=$?")
}
check() { # label condition-result
  if [ "$2" = ok ]; then echo "ok    $1"; else echo "FAIL  $1: $2"; fail=1; fi
}
cwdjson() { jq -n --arg c "$1" '{cwd: $c, hook_event_name: "SessionStart"}'; }

out=$(run "$bare" "$(cwdjson "$TMPDIR/empty")" "$TMPDIR")
[ "$out" = "exit=0" ] && r=ok || r="got: $out"
check "no marker: no output, exit 0" "$r"

out=$(run "$stubs:$bare" "$(cwdjson "$TMPDIR/ts")" "$TMPDIR")
[ "$out" = "exit=0" ] && r=ok || r="got: $out"
check "marker and binary present: no output, exit 0" "$r"

out=$(run "$bare" "$(cwdjson "$TMPDIR/ts")" "$TMPDIR")
body=$(printf '%s\n' "$out" | sed '$d'); code=$(printf '%s\n' "$out" | tail -n 1)
ev=$(printf '%s' "$body" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)
ctx=$(printf '%s' "$body" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
case "$ctx" in *'pnpm add -g typescript-language-server typescript'*) has=1 ;; *) has=0 ;; esac
[ "$code" = "exit=0" ] && [ "$ev" = "SessionStart" ] && [ "$has" = 1 ] && r=ok || r="got: $out"
check "marker, binary absent: JSON with the install command" "$r"

out=$(run "$bare" "this is not json" "$TMPDIR/ts")
body=$(printf '%s\n' "$out" | sed '$d'); code=$(printf '%s\n' "$out" | tail -n 1)
ctx=$(printf '%s' "$body" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
case "$ctx" in *TypeScript*) has=1 ;; *) has=0 ;; esac
[ "$code" = "exit=0" ] && [ "$has" = 1 ] && r=ok || r="got: $out"
check "stdin not JSON: exit 0, falls back to PWD" "$r"

out=$(run "$bare" "" "$TMPDIR/ts")
body=$(printf '%s\n' "$out" | sed '$d'); code=$(printf '%s\n' "$out" | tail -n 1)
ctx=$(printf '%s' "$body" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
case "$ctx" in *TypeScript*) has=1 ;; *) has=0 ;; esac
[ "$code" = "exit=0" ] && [ "$has" = 1 ] && r=ok || r="got: $out"
check "empty stdin: exit 0, falls back to PWD" "$r"

out=$(run "$bare" "$(cwdjson "$TMPDIR/both")" "$TMPDIR")
body=$(printf '%s\n' "$out" | sed '$d'); code=$(printf '%s\n' "$out" | tail -n 1)
ctx=$(printf '%s' "$body" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
case "$ctx" in *TypeScript*) a=1 ;; *) a=0 ;; esac
case "$ctx" in *Python*) b=1 ;; *) b=0 ;; esac
[ "$code" = "exit=0" ] && [ "$a" = 1 ] && [ "$b" = 1 ] && r=ok || r="got: $out"
check "two markers, both binaries absent: both languages named" "$r"

exit $fail
