#!/usr/bin/env bash
# scrub-check.sh — refuse to let private details reach a public repo.
#
# Run before every commit, and again before flipping this repo public:
#   ./tools/scrub-check.sh
#
# Exit 0 = clean, exit 1 = something matched and must be fixed.
#
# The patterns below are the things that would actually cost something if
# published. Internal RFC1918 addresses are deliberately NOT flagged — they're
# meaningless to a reader and the topology is the point of the docs.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

FAIL=0
SCAN_PATHS=(posts docs scripts claude-setup tools README.md)

# This file defines every pattern below, and canary-check.sh plants a fake value
# for each one, so both match nearly everything here by definition. They are exempt
# from the *pattern* checks and deliberately NOT exempt from the literal ones: a
# pattern or a fabricated value living here is the point, a real value never is.
# The canary takes its known-bad literals from the external secrets file at run
# time precisely so it never has to hold one.
SELF=(--exclude=scrub-check.sh --exclude=canary-check.sh)

# Known-bad literals live OUTSIDE this repo — committing a secret to grep for it
# is self-defeating. One value per line, matched as fixed strings.
SECRETS_FILE="${SECRETS_FILE:-$HOME/.local/share/homelab-writeup/known-secrets.txt}"

check() {
  local label="$1" pattern="$2"
  local hits
  hits=$(grep -rIinE --exclude-dir=.git "${SELF[@]}" "$pattern" "${SCAN_PATHS[@]}" 2>/dev/null)
  printf '  %-28s ' "$label"
  if [ -z "$hits" ]; then
    echo "clean"
  else
    echo "FOUND"
    echo "$hits" | sed 's/^/      /'
    FAIL=1
  fi
}


# Like check(), but tolerates a known-good pattern. Used where the generic
# substitute legitimately matches the shape we're hunting for.
check_except() {
  local label="$1" pattern="$2" allow="$3" hits
  hits=$(grep -rIinE --exclude-dir=.git "${SELF[@]}" "$pattern" "${SCAN_PATHS[@]}" 2>/dev/null | grep -vE "$allow")
  printf '  %-28s ' "$label"
  if [ -z "$hits" ]; then echo "clean"; else echo "FOUND"; echo "$hits" | sed 's/^/      /'; FAIL=1; fi
}

echo "=== scrub check ==="

# The one that matters most: a live residential WAN address.
# Any routable public IPv4 in the tree. Implemented as match-all-then-filter
# because grep -E has no negative lookahead — the previous version used (?!...)
# and silently errored on every run, which the script read as "clean".
# Allowed: RFC1918, loopback, link-local, multicast/broadcast, the RFC5737
# documentation ranges, well-known public resolvers, and 1.2.3.x placeholders.
printf '  %-28s ' "public IPv4"
IP_HITS=$(grep -rIonE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' --exclude-dir=.git "${SELF[@]}" "${SCAN_PATHS[@]}" 2>/dev/null \
  | grep -vE ':(10\.|127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|0\.0\.0\.0|255\.|22[4-9]\.|23[0-9]\.)' \
  | grep -vE ':(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)' \
  | grep -vE ':(1\.1\.1\.1|8\.8\.8\.8|8\.8\.4\.4|9\.9\.9\.9)$' \
  | grep -vE ':1\.2\.3\.[0-9]+$')
if [ -z "$IP_HITS" ]; then
  echo "clean"
else
  echo "FOUND"; echo "$IP_HITS" | sed 's/^/      /'; FAIL=1
fi
# Any bare public IPv4 that isn't RFC1918/loopback/docker — catches pasted log lines.

# Hostnames that resolve to a specific house.
# Escaped forms: a value written 203\.0\.113\.7 in a sed script evades a pattern
# for the plain form, because the pattern's escapes match dots, not backslashes.
# Strip backslashes per file, THEN look for known-bad literals — precise, so it
# doesn't fire on every legitimate IP regex.
printf '  %-28s ' "escaped-form leakage"
ESC_HITS=""
if [ -r "${SECRETS_FILE:-$HOME/.local/share/homelab-writeup/known-secrets.txt}" ]; then
  while IFS= read -r f; do
    if tr -d '\\\\' < "$f" | grep -qiF -f "${SECRETS_FILE:-$HOME/.local/share/homelab-writeup/known-secrets.txt}" 2>/dev/null; then
      ESC_HITS="${ESC_HITS}${f}\\n"
    fi
  done < <(find "${SCAN_PATHS[@]}" -type f 2>/dev/null)
  if [ -z "$ESC_HITS" ]; then echo "clean"; else echo "FOUND"; printf "$ESC_HITS" | sed 's/^/      /'; FAIL=1; fi
else
  echo "SKIPPED — no secrets file"
fi
check "duckdns hostnames"    '[a-z0-9-]+\.duckdns\.org'

# Credentials, in any shape.
# Placeholders in *.example files are not secrets; real-looking values are.
check_except "credential values" '(password|passwd|secret|token|api[_-]?key)\s*[=:]\s*["'"'"']?[A-Za-z0-9._/+-]{8,}' 'replace_me|replace-me|changeme|<[a-z][a-z-]*>|your[-_]|xxx+|\.example'
# Known-bad literals live OUTSIDE this repo. Committing a secret in order to
# grep for it is self-defeating — the checker would leak exactly what it exists
# to catch. One value per line, matched as fixed strings.
printf '  %-28s ' "known-bad literals"
if [ -r "$SECRETS_FILE" ]; then
  SECRET_HITS=$(grep -rIinF --exclude-dir=.git -f "$SECRETS_FILE" "${SCAN_PATHS[@]}" 2>/dev/null)
  if [ -z "$SECRET_HITS" ]; then
    echo "clean"
  else
    echo "FOUND"; echo "$SECRET_HITS" | sed 's/^/      /'; FAIL=1
  fi
else
  echo "SKIPPED — no $SECRETS_FILE"
fi
# Names of private-infrastructure credential stores. Deliberately does NOT include
# a script's own documented config path — the filename isn't the secret, the
# contents are, and those are caught by the tracked-env-file check below.
check "private cred stores"  '\bhomelab\.env|gitea-token|\.homelab\b'
check "private key material" 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|(Private|Preshared)Key\s*=\s*[A-Za-z0-9+/]{20,}'
# A wg key is 43 base64 chars + '='. The previous pattern ended in \b, which after
# a '=' only matches if a word character follows — so a key at end of line, which
# is how every real config writes one, could never match. It missed a live server
# PublicKey sitting in the VPN runbook. Allowlist is for CSP sha256- hashes, which
# are the same shape and are not secrets.
check_except "wireguard keys" '\b[A-Za-z0-9+/]{43}=' 'sha256-'

# Personal identifiers that don't belong in a technical writeup.
# Email slipped past every other check for months: no pattern here matched one, and
# a real address reads as ordinary config in a certbot or git example.
check_except "email addresses" '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 'your@email\.com|user@host|@example\.(com|net|org)|noreply@|<EMAIL>'
check "windows user paths"   '/mnt/[a-z]/Users/[A-Za-z0-9._-]+'
check "family references"    '\b(sister|brother|mother|father|wife|cousin)\b'
check "home MAC addresses"   '\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b'
check_except "absolute home paths" '/home/[a-z0-9_-]+/' '/home/homelab/'

# An actual env file in the tree is the real risk — a filename mentioned in docs is not.
printf '  %-28s ' "env files present"
ENVFILES=$(find . -name '*.env' -not -name '*.env.example' -not -path './.git/*' 2>/dev/null)
if [ -z "$ENVFILES" ]; then
  echo "clean"
else
  echo "FOUND"; echo "$ENVFILES" | sed 's/^/      /'; FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS — nothing flagged."
else
  echo "FAIL — fix the matches above before committing."
fi
exit "$FAIL"
