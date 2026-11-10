#!/bin/sh
# Render every subject script in subjects/ to out/<name>.png (and the Marianne bust). Usage: sh render_all.sh [name ...]
cd "$(dirname "$0")" || exit 1
names="$*"
if [ -z "$names" ]; then
  for f in subjects/*.py; do n=${f#subjects/}; names="$names ${n%.py}"; done
fi
for n in $names; do
  if blender -b -P "subjects/$n.py" >"out/$n.log" 2>&1 && grep -q Saved "out/$n.log"; then
    printf 'ok   %s\n' "$n"; rm -f "out/$n.log"
  else
    printf 'KO   %s (see out/%s.log)\n' "$n" "$n"
  fi
done
