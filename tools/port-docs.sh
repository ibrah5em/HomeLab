#!/usr/bin/env bash
# Port the private runbooks into this repo, sanitized.
#
# The substitution map is NOT in this repo — it necessarily contains every real
# value being replaced (public addresses, hostnames, account names), so shipping
# it would defeat the point. It lives outside the tree:
#
#   MAP=~/.local/share/homelab-writeup/map-docs.sed
#
# Each line is a plain sed expression, e.g.  s/<real-value>/<placeholder>/g
set -euo pipefail

SRC="${SRC:-$HOME/HomeLab/docs}"
DST="${DST:-$(dirname "$0")/../docs}"
MAP="${MAP:-$HOME/.local/share/homelab-writeup/map-docs.sed}"

[ -r "$MAP" ] || { echo "missing substitution map: $MAP" >&2; exit 1; }

banner() {
  cat <<'EOF'
> **Sanitized for publication.** This is the real operational runbook, with
> identifying values substituted: public addresses, hostnames, MAC addresses and
> account names are placeholders, and paths are genericized. Internal RFC1918
> addresses are kept — they're meaningless to a reader and the topology is the
> point. Third-party project names are replaced with placeholders.
>
> Both machines were decommissioned in August 2026. Nothing described here is running.

EOF
}

strip_retire() { awk '/^> ## ⛔ RETIRED/{skip=1} skip && /^---$/{skip=0; next} !skip'; }

port() { # src dst title
  { head -1 "$1" | sed "s/.*/# $3/"; echo; banner; tail -n +2 "$1" | strip_retire | sed -f "$MAP"; } > "$2"
  echo "  ported: $(basename "$2")  ($(wc -l < "$2") lines)"
}

port "$SRC/x-server-docs.md" "$DST/public-server-runbook.md" "Public server — full runbook"
port "$SRC/n-server-docs.md" "$DST/lan-server-runbook.md"    "LAN server — full runbook"
