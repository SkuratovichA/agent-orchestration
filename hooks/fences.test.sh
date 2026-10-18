#!/bin/sh
# Pins the fence column of the two agent tables (the agent-orchestration skill's roster and the README's) to the
# maxTurns of the agents' frontmatter, which is also where turn-budget.sh reads the fence. Run: sh hooks/fences.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}

frontmatter_fence() { # agent file; the maxTurns between the first two "---" lines
  awk '/^---/ { n++; next } n == 1 && /^maxTurns:/ { print $2; exit }' "$1"
}
table_cell() { # doc, agent type, column number; the cell of the row that begins with the type's name
  awk -F'|' -v type="\`agent-orchestration:$2\`" -v col="$3" '{ for (i = 2; i <= 4; i++) gsub(/^ +| +$/, "", $i) } $2 == type { print $col; exit }' "$1"
}
table_rows() { # doc; how many rows begin with an agent type of this plugin
  grep -c -E '^\| `agent-orchestration:[a-z-]+` \|' "$1"
}
header_cell() { # doc, column number; the title of that column
  awk -F'|' -v col="$2" '$2 ~ /Agent type/ { gsub(/^ +| +$/, "", $col); print $col; exit }' "$1"
}
equal() { [ "$1" = "$2" ]; }

agents=0
for file in "$root"/agents/*.md; do
  agents=$((agents + 1))
  name=$(basename "$file" .md)
  fence=$(frontmatter_fence "$file")
  check "$name has a fence in its frontmatter" sh -c 'case "$1" in ""|*[!0-9]*) exit 1 ;; esac' sh "$fence"
  for doc in skills/agent-orchestration/SKILL.md README.md; do
    check "$doc: the fence of $name is $fence, as in agents/$name.md" equal "$(table_cell "$root/$doc" "$name" 4)" "$fence"
  done
done
for doc in skills/agent-orchestration/SKILL.md README.md; do
  check "$doc: the column that holds the fences is titled Fence" equal "$(header_cell "$root/$doc" 4)" Fence
  check "$doc: the table has one row per agent file ($agents)" equal "$(table_rows "$root/$doc")" "$agents"
done

exit $fail
