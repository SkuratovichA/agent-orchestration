#!/bin/sh
# Pins builder-xl to builder-l: an agent definition cannot import another, so builder-xl is a copy of builder-l with another name, description and effort, and the two bodies must stay identical. Also pins the efforts of the three builders and the rule that builder-xl is never picked by the orchestrator.
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}

body() { awk '/^---/ { marks++; next } marks >= 2 { print }' "$root/agents/$1.md"; }
effort() { awk '/^---/ { marks++; next } marks == 1 && $1 == "effort:" { print $2; exit }' "$root/agents/$1.md"; }
model() { awk '/^---/ { marks++; next } marks == 1 && $1 == "model:" { print $2; exit }' "$root/agents/$1.md"; }
equal() { [ "$1" = "$2" ]; }

check "builder-xl has the body of builder-l" equal "$(body builder-xl)" "$(body builder-l)"
check "builder-m runs at medium" equal "$(effort builder-m)" medium
check "builder-l runs at high" equal "$(effort builder-l)" high
check "builder-xl runs at xhigh" equal "$(effort builder-xl)" xhigh
for name in builder-m builder-l builder-xl; do
  check "$name runs on sonnet" equal "$(model "$name")" sonnet
done
check "the description of builder-xl says the orchestrator never picks it" grep -q 'The orchestrator never picks it' "$root/agents/builder-xl.md"
check "the agorch skill says builder-xl is spawned only on the user's request" grep -q 'builder-xl` is spawned only on the user' "$root/skills/agorch/SKILL.md"

exit $fail
