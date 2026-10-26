#!/bin/sh
# Cases for the size of the skills. Run: sh hooks/skill-size.test.sh
# After a compaction a re-attached skill keeps only its first 5,000 tokens, so a rule past that point silently disappears; 15500 bytes is the budget that keeps every rule inside it.
root="$(cd "$(dirname "$0")/.." && pwd)"
limit=15500
fail=0
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  size=$(wc -c < "$f" | tr -d ' ')
  name=${f#"$root"/}
  if [ "$size" -le "$limit" ]; then echo "ok    $name is $size bytes"; else echo "FAIL  $name is $size bytes, over $limit"; fail=1; fi
done
exit $fail
