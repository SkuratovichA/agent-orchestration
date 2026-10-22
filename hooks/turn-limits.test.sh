#!/bin/sh
# Pins the turn limits: references/turn-limits.tsv has one row for each agent file and no other, the frontmatter maxTurns of each agent is a hard ceiling above its limit, and the turn limit column of the two agent tables (the agent-orchestration skill's roster and the README's) holds the limit of the table. Run: sh hooks/turn-limits.test.sh
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/hooks/lib.sh"
tsv="$root/references/turn-limits.tsv"
fail=0
check() { # label command... ; the command succeeds when the row holds
  label=$1; shift
  if "$@"; then echo "ok    $label"; else echo "FAIL  $label"; fail=1; fi
}

tsv_rows() { # name; how many rows of the table name the agent
  awk -F'\t' -v name="$1" '/^#/ || NF == 0 { next } $1 == name { n++ } END { print n + 0 }' "$tsv"
}
tsv_limit() { # name; the limit of the first row of the agent
  awk -F'\t' -v name="$1" '/^#/ || NF == 0 { next } $1 == name { print $2; exit }' "$tsv"
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
number() { # value; a positive integer
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -gt 0 ]
}
above() { [ "$1" -gt "$2" ]; } # first number is greater than the second
header_is_a_comment() { [ "$(sed 1q "$tsv")" = "# agent$(printf '\t')turn limit" ]; }

check "the table of turn limits begins with its header line" header_is_a_comment

agents=0
for file in "$root"/agents/*.md; do
  agents=$((agents + 1))
  name=$(basename "$file" .md)
  limit=$(tsv_limit "$name")
  ceiling=$(max_turns "$root" "$name")
  check "$name has exactly one row in references/turn-limits.tsv" equal "$(tsv_rows "$name")" 1
  check "$name has a turn limit that is a positive integer ($limit)" number "$limit"
  check "$name has a maxTurns in its frontmatter that is a positive integer ($ceiling)" number "$ceiling"
  check "the maxTurns of $name ($ceiling) is above its turn limit ($limit)" above "$ceiling" "$limit"
  for doc in skills/agent-orchestration/SKILL.md README.md; do
    check "$doc: the turn limit of $name is $limit, as in references/turn-limits.tsv" equal "$(table_cell "$root/$doc" "$name" 4)" "$limit"
  done
done
for doc in skills/agent-orchestration/SKILL.md README.md; do
  check "$doc: the column that holds the turn limits is titled Turn limit" equal "$(header_cell "$root/$doc" 4)" "Turn limit"
  check "$doc: the table has one row per agent file ($agents)" equal "$(table_rows "$root/$doc")" "$agents"
done

# Every row of the table names an agent file.
rows=$(awk -F'\t' '/^#/ || NF == 0 { next } { print $1 }' "$tsv")
for row in $rows; do
  check "the row $row of references/turn-limits.tsv names an agent file" [ -f "$root/agents/$row.md" ]
done
check "the table has one row per agent file ($agents)" equal "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "$agents"

exit $fail
