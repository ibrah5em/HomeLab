#!/usr/bin/env bash
# Port the private .claude/ agent setup into this repo, sanitized and de-personalized.
#
# As with port-docs.sh, the substitution map is deliberately NOT in this repo —
# it contains the real values. It lives at:
#
#   MAP=~/.local/share/homelab-writeup/map-claude.sed
set -euo pipefail

SRC="${SRC:-$HOME/HomeLab/.claude}"
DST="${DST:-$(dirname "$0")/../claude-setup}"
MAP="${MAP:-$HOME/.local/share/homelab-writeup/map-claude.sed}"

[ -r "$MAP" ] || { echo "missing substitution map: $MAP" >&2; exit 1; }

# keep the hand-written README, replace everything else
find "$DST" -mindepth 1 -not -name README.md -delete 2>/dev/null || true

find "$SRC" -type f | while read -r f; do
  rel="${f#$SRC/}"
  mkdir -p "$DST/$(dirname "$rel")"
  sed -f "$MAP" < "$f" > "$DST/$rel"
done

echo "ported $(find "$DST" -type f -not -name README.md | wc -l) files"
