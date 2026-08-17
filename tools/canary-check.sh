#!/usr/bin/env bash
# canary-check.sh — prove scrub-check.sh can actually fail.
#
#   ./tools/canary-check.sh
#
# Exit 0 = every check fired on a planted value and the clean tree still passes.
#
# The whole series is about failures that report success, and the scrub checker
# did it too: four broken checks printed "clean" for weeks, and a fifth — the
# WireGuard pattern — had never once been able to match a real key, because it
# ended in \b after an '=' and a key at end of line has no word char to bound
# against. It missed a live server PublicKey in the VPN runbook.
#
# None of those are visible by reading. All five die the moment you plant a value
# and watch the check print "clean" anyway. So: if a check can't be made to fail
# on demand, it doesn't get believed when it passes.
#
# This drives the real scrub-check.sh rather than re-declaring its patterns —
# a copy of the patterns here would be one more thing to drift out of sync.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

SCRUB=./tools/scrub-check.sh
SECRETS_FILE="${SECRETS_FILE:-$HOME/.local/share/homelab-writeup/known-secrets.txt}"
CANARY=docs/.canary-planted.md
CANARY_ENV=docs/.canary-planted.env
FAIL=0

# Planted values must never survive a failed run.
cleanup() { rm -f "$CANARY" "$CANARY_ENV"; }
trap cleanup EXIT INT TERM

# expect_fires <label> <file> <content>
# Plants content, runs the real checker, and asserts that <label> reported FOUND.
# Asserting on the label rather than just the exit code is what catches a check
# that passes only because some *other* check tripped over the same value.
expect_fires() {
  local label="$1" file="$2" content="$3" out
  printf '%s\n' "$content" > "$file"
  out=$("$SCRUB" 2>&1)
  cleanup
  if printf '%s' "$out" | grep -qE "^  ${label} +FOUND"; then
    printf '  %-28s %s\n' "$label" "fails on demand"
  else
    printf '  %-28s %s\n' "$label" "*** DID NOT FIRE — check is blind ***"
    FAIL=1
  fi
}

echo "=== canary: every check must fail on a planted value ==="

expect_fires "public IPv4"          "$CANARY" 'peer endpoint 198.18.7.42:51820'
expect_fires "duckdns hostnames"    "$CANARY" 'server_name myrealbox.duckdns.org;'
expect_fires "credential values"    "$CANARY" 'password = s3cretValue99'
expect_fires "private cred stores"  "$CANARY" 'reads the gitea-token file'
expect_fires "private key material" "$CANARY" '-----BEGIN OPENSSH PRIVATE KEY-----'
expect_fires "wireguard keys"       "$CANARY" 'PublicKey = E/ghG1DleWw5G3lRd2CONx6WGKkDn9Vig+hnu0HplsE='
expect_fires "email addresses"      "$CANARY" 'certbot --email real.person@gmail.com'
expect_fires "windows user paths"   "$CANARY" 'cd /mnt/c/Users/Someone/Desktop'
# Capitalised on purpose: the original bug was -I read as ignore-case, and the
# lowercase pattern walked past exactly this.
expect_fires "family references"    "$CANARY" 'My Sister set up the router.'
expect_fires "home MAC addresses"   "$CANARY" 'dhcp lease for 3c:22:fb:9a:01:ef'
expect_fires "absolute home paths"  "$CANARY" 'lives in /home/realuser/projects'
expect_fires "env files present"    "$CANARY_ENV" 'TOKEN=doesnotmatter'

# The last two need a real known-bad literal, which by design lives outside this
# repo. Taking it from the external file keeps it out of the tree and the history
# while still testing the checks that matter most.
if [ -r "$SECRETS_FILE" ]; then
  LITERAL=$(grep -m1 . "$SECRETS_FILE")
  expect_fires "known-bad literals"  "$CANARY" "value $LITERAL in a doc"
  # The escaped form is what hid the port scripts: a sed script writing
  # 203\.0\.113\.7 does not match a pattern for the plain form.
  expect_fires "escaped-form leakage" "$CANARY" "s/$(printf '%s' "$LITERAL" | sed 's/\./\\\\./g')/<PLACEHOLDER>/g"
else
  printf '  %-28s %s\n' "known-bad literals" "SKIPPED — no secrets file"
  printf '  %-28s %s\n' "escaped-form leakage" "SKIPPED — no secrets file"
fi

# The other direction. A checker that fires on everything is as useless as one
# that fires on nothing.
echo
printf '  %-28s ' "clean tree still passes"
if "$SCRUB" >/dev/null 2>&1; then
  echo "yes"
else
  echo "*** NO — scrub-check fails on the committed tree ***"
  FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS — every check can be made to fail, and the tree is clean."
else
  echo "FAIL — a check above cannot detect what it exists to detect."
fi
exit "$FAIL"
