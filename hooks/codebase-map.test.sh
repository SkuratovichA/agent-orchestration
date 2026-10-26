#!/bin/sh
# Cases for bin/codebase-map and hooks/map-check.sh. Run: sh hooks/codebase-map.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
cmd="$root/bin/codebase-map"
hook="$root/hooks/map-check.sh"
shpath=$(command -v sh)
TMPDIR=$(mktemp -d); export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT
fail=0
n=0
tab=$(printf '\t')

# Each case gets its own cache and repository; the real cache is never touched.
fresh() { n=$((n + 1)); XDG_CACHE_HOME="$TMPDIR/c$n/cache"; export XDG_CACHE_HOME; repo="$TMPDIR/c$n/repo"; mkdir -p "$repo"; git -C "$repo" init -q; }
commit() { # repo message
  git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "$2"
}
put() { # repo path...
  r=$1; shift
  for f in "$@"; do mkdir -p "$r/$(dirname "$f")"; echo x > "$r/$f"; done
}
run() { # directory args...
  d=$1; shift
  (cd "$d" && "$shpath" "$cmd" "$@" 2>&1; echo "exit=$?")
}
check() { if [ "$2" = ok ]; then echo "ok    $1"; else echo "FAIL  $1: $2"; fail=1; fi; }
has() { # label output needle
  case "$2" in *"$3"*) r=ok ;; *) r="missing '$3' in: $2" ;; esac; check "$1" "$r"
}
lacks() { # label output needle
  case "$2" in *"$3"*) r="unexpected '$3' in: $2" ;; *) r=ok ;; esac; check "$1" "$r"
}
body() { printf '%s\n' "$1" | sed '$d'; }
code() { printf '%s\n' "$1" | tail -n 1; }
hookrun() { # directory
  (jq -n --arg c "$1" '{cwd: $c}' | (cd / && "$shpath" "$hook"); echo "exit=$?")
}

# 1
fresh; put "$repo" a.txt; commit "$repo" init
out=$(run "$repo" dir); p=$(body "$out")
case "$p" in "$XDG_CACHE_HOME/agent-orchestration/maps/"*) r=ok ;; *) r="got: $p" ;; esac
[ -d "$p/modules" ] || r="no modules/ in $p"
[ "$(code "$out")" = exit=0 ] || r="got: $out"
check "dir prints a path under the cache and creates modules/" "$r"

# 2
d1=$p
git -C "$repo" worktree add -q "$TMPDIR/c$n/wt" -b other 2>/dev/null
d2=$(body "$(run "$TMPDIR/c$n/wt" dir)")
[ "$d1" = "$d2" ] && r=ok || r="main $d1, worktree $d2"; check "dir from a second worktree prints the same path" "$r"
mkdir "$TMPDIR/c$n/repo2"; git -C "$TMPDIR/c$n/repo2" init -q
d3=$(body "$(run "$TMPDIR/c$n/repo2" dir)")
[ "$d1" != "$d3" ] && r=ok || r="same path $d1"; check "dir of a different repository differs" "$r"

# 3
fresh; mkdir -p "$TMPDIR/c$n/plain"
out=$(run "$TMPDIR/c$n/plain" dir); [ "$(code "$out")" = exit=1 ] && r=ok || r="got: $out"
check "dir outside a git repository exits 1" "$r"

# 4
fresh; put "$repo" a.txt; commit "$repo" init
out=$(run "$repo" status); has "status without a map says built: none" "$out" "built: none"
out=$(run "$repo" status --oneline); [ "$out" = "exit=0" ] && r=ok || r="got: $out"
check "status --oneline without a map prints nothing" "$r"

# 5
run "$repo" stamp >/dev/null
out=$(run "$repo" status)
has "after stamp: 0 commits behind" "$out" "(0 commits behind HEAD"
has "after stamp: refresh none" "$out" "refresh: none"
out=$(run "$repo" status --oneline); has "after stamp: oneline says nothing changed" "$out" "nothing changed since."

# 6
mapdir=$(body "$(run "$repo" dir)")
printf 'services/a\tservices-a\t1\nservices/b\tservices-b\t1\n' > "$mapdir/modules.tsv"
put "$repo" services/a/x.ts; commit "$repo" "change a"
out=$(run "$repo" status)
has "a change under services/a lists services/a" "$out" "refresh: services/a"
lacks "services/b is not listed" "$out" "services/b"
has "one commit behind" "$out" "(1 commits behind HEAD"
out=$(run "$repo" status --oneline)
has "oneline names the module" "$out" "in modules: services/a."

# 7
printf '.\troot\t1\nservices/a\tservices-a\t1\n' > "$mapdir/modules.tsv"
put "$repo" top.md docs/note.md; commit "$repo" root
out=$(run "$repo" status)
has "a root file maps to module ." "$out" "refresh: ., services/a"
has "a file under no module is unmapped" "$out" "unmapped: 1 changed files outside every module"

# 8
fresh; put "$repo" a.txt; commit "$repo" init
mapdir=$(body "$(run "$repo" dir)"); echo 1234567890abcdef1234567890abcdef12345678 > "$mapdir/commit"
out=$(run "$repo" status); has "a sha the repository does not have asks for a rebuild" "$out" "built: 1234567, this repository does not have that commit: rebuild"
lacks "no changed line for a foreign sha" "$out" "changed:"
out=$(run "$repo" status --oneline); has "oneline wording for a foreign sha" "$out" "does not have that commit; rebuild it."

# 9
fresh; put "$repo" packages/x/1.ts packages/x/2.ts packages/y/1.ts packages/y/2.ts packages/y/3.ts packages/y/4.ts packages/z.ts src/a.ts README.md .github/w.yml node_modules/m/i.js
commit "$repo" tree
out=$(run "$repo" modules 3)
want=$(printf '.\troot\t1\npackages\tpackages-top\t1\npackages/x\tpackages-x\t2\npackages/y\tpackages-y\t4\nsrc\tsrc\t1\nexit=0')
[ "$out" = "$want" ] && r=ok || r="got: $out"
check "modules 3 splits packages and skips dot and node_modules directories" "$r"
out=$(run "$repo" modules); has "default limit keeps packages as one module" "$out" "packages${tab}packages${tab}7"

# 10
fresh; mkdir -p "$TMPDIR/c$n/plain"
out=$(hookrun "$TMPDIR/c$n/plain"); [ "$out" = "exit=0" ] && r=ok || r="got: $out"; check "hook is silent outside a git repository" "$r"
put "$repo" a.txt; commit "$repo" init
out=$(hookrun "$repo"); [ "$out" = "exit=0" ] && r=ok || r="got: $out"; check "hook is silent in a repository with no map" "$r"
run "$repo" stamp >/dev/null
out=$(hookrun "$repo"); ctx=$(body "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
has "hook context names INDEX.md" "$ctx" "INDEX.md"
has "hook context names the skill" "$ctx" "agent-orchestration:mapping-codebases"
[ "$(code "$out")" = "exit=0" ] && r=ok || r="got: $out"; check "hook exits 0 with a map" "$r"

# 11
out=$(run "$repo" bogus); [ "$(code "$out")" = exit=2 ] && r=ok || r="got: $out"; check "unknown subcommand exits 2" "$r"

# 12: a build commit that is no ancestor of HEAD still counts; only a missing commit is foreign
fresh; put "$repo" a.txt; commit "$repo" init
run "$repo" stamp >/dev/null; mapdir=$(body "$(run "$repo" dir)")
printf 'services/a\tservices-a\t1\nservices/b\tservices-b\t1\n' > "$mapdir/modules.tsv"
put "$repo" services/a/x.ts; git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --amend -m amended
out=$(run "$repo" status)
lacks "after an amend the build commit is not foreign" "$out" "does not have that commit"
has "after an amend the changed module is listed" "$out" "refresh: services/a"
has "after an amend status says it is no ancestor" "$out" "not an ancestor of HEAD"
lacks "after an amend status counts no commits behind" "$out" "commits behind"
out=$(run "$repo" status --oneline)
has "after an amend oneline lists the module" "$out" "in modules: services/a"
has "after an amend oneline says it is no ancestor" "$out" "not an ancestor of HEAD"
lacks "after an amend oneline does not ask for a rebuild" "$out" "rebuild"

fresh; put "$repo" a.txt; commit "$repo" init
git -C "$repo" checkout -q -b other; put "$repo" services/a/x.ts; commit "$repo" "on other"
run "$repo" stamp >/dev/null; mapdir=$(body "$(run "$repo" dir)")
printf 'services/a\tservices-a\t1\nservices/b\tservices-b\t1\n' > "$mapdir/modules.tsv"
git -C "$repo" checkout -q -; put "$repo" services/b/y.ts; commit "$repo" "on the first branch"
out=$(run "$repo" status)
lacks "a stamp from another branch is not foreign" "$out" "does not have that commit"
has "a stamp from another branch lists the modules that differ" "$out" "refresh: services/a, services/b"
has "a stamp from another branch says it is no ancestor" "$out" "not an ancestor of HEAD"

fresh; put "$repo" a.txt; commit "$repo" init
mapdir=$(body "$(run "$repo" dir)"); echo 1234567890abcdef1234567890abcdef12345678 > "$mapdir/commit"
out=$(run "$repo" status); lacks "a missing sha is not called a non-ancestor" "$out" "ancestor"

# 13: modules lists root-relative paths from a subdirectory
fresh; put "$repo" packages/foo/a.ts src/b.ts top.md; commit "$repo" tree
out=$(run "$repo/packages/foo" modules)
has "modules from a subdirectory lists the root module" "$out" ".${tab}root${tab}1"
has "modules from a subdirectory lists a sibling tree" "$out" "src${tab}src${tab}1"
has "modules from a subdirectory lists the directory by its root-relative path" "$out" "packages${tab}packages${tab}1"

# 14: git mv across modules lists both; a non-ASCII module name is listed by name
fresh; put "$repo" services/a/f.ts; commit "$repo" init
run "$repo" stamp >/dev/null; mapdir=$(body "$(run "$repo" dir)")
printf 'services/a\tservices-a\t1\nservices/b\tservices-b\t1\n' > "$mapdir/modules.tsv"
mkdir -p "$repo/services/b"; git -C "$repo" mv services/a/f.ts services/b/f.ts; commit "$repo" "move"
out=$(run "$repo" status); has "a move between modules lists both modules" "$out" "refresh: services/a, services/b"
fresh; put "$repo" "café/f.ts" top.md; commit "$repo" init
out=$(run "$repo" modules); has "modules lists a non-ASCII directory by name" "$out" "café${tab}caf"
run "$repo" stamp >/dev/null; mapdir=$(body "$(run "$repo" dir)")
printf 'café\tcaf-\t1\n' > "$mapdir/modules.tsv"
put "$repo" "café/g.ts"; commit "$repo" "more"
out=$(run "$repo" status); has "a changed file under a non-ASCII module is mapped" "$out" "refresh: café"
lacks "and not left unmapped" "$out" "unmapped"

# 15: spaces in the repository path and in XDG_CACHE_HOME
n=$((n + 1)); XDG_CACHE_HOME="$TMPDIR/c$n/ca che"; export XDG_CACHE_HOME; repo="$TMPDIR/c$n/re po"; mkdir -p "$repo"; git -C "$repo" init -q
put "$repo" a.txt; commit "$repo" init
out=$(run "$repo" stamp); has "stamp works with spaces in both paths" "$out" "stamped "
out=$(run "$repo" status); has "status works with spaces in both paths" "$out" "map: $XDG_CACHE_HOME/agent-orchestration/maps/re-po-"
has "status after a stamp with spaces: 0 commits behind" "$out" "(0 commits behind HEAD"
out=$(hookrun "$repo"); ctx=$(body "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
has "the hook works with spaces in both paths" "$ctx" "INDEX.md"

# 16: no commit, detached HEAD, bad arguments
fresh
out=$(run "$repo" stamp); [ "$(code "$out")" = exit=1 ] && r=ok || r="got: $out"; check "stamp in a repository with no commit exits 1" "$r"
has "and says why" "$out" "the repository has no commit yet"
fresh; put "$repo" a.txt; commit "$repo" init
run "$repo" stamp >/dev/null; put "$repo" b.txt; commit "$repo" second
git -C "$repo" checkout -q --detach HEAD
out=$(run "$repo" status); has "status on a detached HEAD counts the commits behind" "$out" "(1 commits behind HEAD"
[ "$(code "$out")" = exit=0 ] && r=ok || r="got: $out"; check "and exits 0" "$r"
out=$(run "$repo" modules 0); [ "$(code "$out")" = exit=2 ] && r=ok || r="got: $out"; check "modules 0 exits 2" "$r"
out=$(run "$repo" modules abc); [ "$(code "$out")" = exit=2 ] && r=ok || r="got: $out"; check "modules abc exits 2" "$r"

# 17: the hook
out=$( (cd "$repo" && printf 'not json' | "$shpath" "$hook"; echo "exit=$?") )
ctx=$(body "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
has "the hook falls back to the working directory on non-JSON stdin" "$ctx" "INDEX.md"
[ "$(code "$out")" = "exit=0" ] && r=ok || r="got: $out"; check "and exits 0" "$r"
# A relative $0 must still find the plugin: root is resolved before the hook changes directory.
out=$( (cd "$root" && printf '{"cwd":"%s"}' "$repo" | "$shpath" hooks/map-check.sh; echo "exit=$?") )
ctx=$(body "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
has "the hook run through a relative path prints its line" "$ctx" "INDEX.md"
[ "$(code "$out")" = "exit=0" ] && r=ok || r="got: $out"; check "and exits 0 through a relative path" "$r"
if jq -e '[.hooks.SessionStart[] | select(any(.hooks[]; .command | contains("map-check.sh"))) | .matcher] | any(contains("startup") and contains("resume") and contains("clear") and contains("compact"))' "$root/hooks/hooks.json" >/dev/null 2>&1; then r=ok; else r="matcher of map-check.sh lacks one of startup, resume, clear, compact"; fi
check "hooks.json runs map-check.sh on startup, resume, clear and compact" "$r"

exit $fail
