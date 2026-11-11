#!/bin/sh
# Pins the turn limits: references/turn-limits.tsv has one row for each agent file and no other, the frontmatter maxTurns of each agent is a hard ceiling above its limit, and the turn limit column of the two agent tables (the agorch skill's roster and the README's) holds the limit of the table. Run: sh hooks/turn-limits.test.sh
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
  awk -F'|' -v type="\`agorch:$2\`" -v col="$3" '{ for (i = 2; i <= 4; i++) gsub(/^ +| +$/, "", $i) } $2 == type { print $col; exit }' "$1"
}
table_rows() { # doc; how many rows begin with an agent type of this plugin
  grep -c -E '^\| `agorch:[a-z-]+` \|' "$1"
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
at_least() { [ "$1" -ge "$2" ]; } # first number is at least the second
number_or_none() { [ "$1" = none ] || number "$1"; }
window_ok() { # agent name; the reader compacts at 100000, the lowest window Claude Code takes, because Haiku 5.5 prices every token of a prompt over 100,000 at five times the rate; every other type compacts at 250000, the window measured in the README under "Why the builders and reviewers compact at 250K"
  value=$(awk '/^---/ { marks++; next } marks == 1 && $1 == "autoCompactWindow:" { print $2; exit }' "$root/agents/$1.md")
  number "$value" || return 1
  if [ "$1" = reader ]; then [ "$value" -eq 100000 ]; else [ "$value" -eq 250000 ]; fi
}
header_is_a_comment() { [ "$(sed 1q "$tsv")" = "# agent$(printf '\t')turn limit" ]; }

check "the table of turn limits begins with its header line" header_is_a_comment

agents=0
for file in "$root"/agents/*.md; do
  agents=$((agents + 1))
  name=$(basename "$file" .md)
  limit=$(tsv_limit "$name")
  ceiling=$(max_turns "$root" "$name")
  check "$name has exactly one row in references/turn-limits.tsv" equal "$(tsv_rows "$name")" 1
  check "$name has a turn limit that is a positive integer or none ($limit)" number_or_none "$limit"
  check "$name has a maxTurns in its frontmatter that is a positive integer ($ceiling)" number "$ceiling"
  if [ "$limit" = none ]; then
    check "$name has no turn limit, so its maxTurns ($ceiling) is out of reach of a batch: at least 10000" at_least "$ceiling" 10000
  else
    check "the maxTurns of $name ($ceiling) is above its turn limit ($limit)" above "$ceiling" "$limit"
  fi
  check "$name has the autoCompactWindow its model needs in its frontmatter (reader 100000, every other type 250000)" window_ok "$name"
  for doc in skills/agorch/SKILL.md README.md; do
    check "$doc: the turn limit of $name is $limit, as in references/turn-limits.tsv" equal "$(table_cell "$root/$doc" "$name" 4)" "$limit"
  done
done
for doc in skills/agorch/SKILL.md README.md; do
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
