#!/bin/bash
# ban-ip.sh — manage nginx-level IP bans, with an auto-ban mode driven by access logs.
#
# Usage:
#   ban-ip.sh ban 203.0.113.7                  # ban a single address
#   ban-ip.sh ban 203.0.113.0/24               # ban a range
#   ban-ip.sh ban 203.0.113.7 "env scanner"    # ban with a reason
#   ban-ip.sh unban 203.0.113.7
#   ban-ip.sh list
#   ban-ip.sh check 203.0.113.7
#   ban-ip.sh auto-ban                         # ban repeat offenders from recent logs
#
# HOW IT WORKS
#   Maintains a single file of `deny <addr>;` directives, included inside every
#   nginx server block. Adding or removing an entry reloads nginx — after
#   testing the config, so a bad entry can't take the proxy down.
#
# SETUP (once)
#   1. touch ~/docker/banned-ips.conf
#   2. Mount it read-only into the nginx container:
#        - ./banned-ips.conf:/etc/nginx/banned-ips.conf:ro
#   3. Inside EACH server {} block, after the listen directives:
#        include /etc/nginx/banned-ips.conf;
#   4. Recreate nginx (`up -d`, not `restart` — restart won't pick up a new mount)
#
# ── AUTO-BAN SEMANTICS — read before asking "why wasn't X banned?" ──────────
#
#   auto-ban bans an address only if it produced more than AUTO_BAN_THRESHOLD
#   responses with status 403 or 444, within the last AUTO_BAN_LOOKBACK lines
#   of the access log.
#
#   It is deliberately blind to:
#     - 404s (a probe for something you never had isn't evidence of much)
#     - low-volume scanners under the threshold
#     - address-rotating scanners, which never accumulate a count
#     - anything that scrolled out of the lookback window
#
#   Being explicit about what a rule does NOT catch is what stops you trusting
#   it to catch something it was never going to.
#
# ⚠ IF THIS FILE IS ALSO DEPLOYED FROM SOURCE CONTROL, YOUR DEPLOY MUST MERGE.
#   A deploy that copies the repo's version over the live one silently discards
#   every ban added since the last commit. Union both sides so a deploy can only
#   ADD entries — and note the trade-off: un-banning then requires removing the
#   address from both the server and the repo, or the next deploy resurrects it.

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

BANFILE="${BANFILE:-$HOME/docker/banned-ips.conf}"
COMPOSE_FILE="${COMPOSE_FILE:-$HOME/docker/docker-compose.yml}"
LOG_FILE="${LOG_FILE:-$HOME/docker/nginx-logs/access.log}"

# Your own public address, so the script refuses to lock you out.
# Set it in the environment; leaving it empty just disables that guard.
HOME_IP="${HOME_IP:-}"

AUTO_BAN_THRESHOLD="${AUTO_BAN_THRESHOLD:-20}"
AUTO_BAN_LOOKBACK="${AUTO_BAN_LOOKBACK:-5000}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ ! -f "$BANFILE" ]]; then
    printf '# nginx IP ban list — managed by ban-ip.sh\n# Format: deny <addr>; # reason | date\n' > "$BANFILE"
    echo -e "${YELLOW}Created $BANFILE — mount it and include it in your server blocks.${NC}"
fi

# ── Helpers ─────────────────────────────────────────────────────────────────

reload_nginx() {
    echo -e "${CYAN}Testing nginx config...${NC}"
    # Test inside the running container — it already has the certs and mounts.
    if docker compose -f "$COMPOSE_FILE" exec nginx nginx -t 2>&1; then
        echo -e "${CYAN}Reloading...${NC}"
        docker compose -f "$COMPOSE_FILE" exec nginx nginx -s reload 2>&1
        echo -e "${GREEN}Done.${NC}"
    else
        echo -e "${RED}nginx config test FAILED — ban NOT applied${NC}"
        return 1
    fi
}

is_internal() { [[ "$1" =~ ^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; }

ban_ip() {
    local ip="$1" reason="${2:-manual ban}"

    if ! echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$'; then
        echo -e "${RED}Invalid address: $ip${NC}"; return 1
    fi
    if [[ -n "$HOME_IP" && "$ip" == "$HOME_IP" ]]; then
        echo -e "${RED}Refusing to ban your own address ($HOME_IP)${NC}"; return 1
    fi
    if is_internal "$ip"; then
        echo -e "${RED}Refusing to ban internal address: $ip${NC}"; return 1
    fi
    if grep -q "deny $ip;" "$BANFILE" 2>/dev/null; then
        echo -e "${YELLOW}$ip is already banned${NC}"; return 0
    fi

    echo "deny $ip; # $reason | $(date '+%Y-%m-%d %H:%M')" >> "$BANFILE"
    echo -e "${RED}Banned: $ip${NC} — $reason"
    reload_nginx
}

unban_ip() {
    local ip="$1"
    grep -q "deny $ip;" "$BANFILE" 2>/dev/null || {
        echo -e "${YELLOW}$ip is not in the ban list${NC}"; return 0; }
    sed -i "\|deny $ip;|d" "$BANFILE"
    echo -e "${GREEN}Unbanned: $ip${NC}"
    echo -e "${YELLOW}Note: if this file is deployed from source control, remove it there too.${NC}"
    reload_nginx
}

list_bans() {
    echo -e "${BOLD}${CYAN}=== BANNED ===${NC}\n"
    local count=0 ip comment
    while IFS= read -r line; do
        [[ "$line" =~ ^# || -z "$line" ]] && continue
        ip=$(echo "$line" | sed 's/deny \([^;]*\);.*/\1/')
        comment=$(echo "$line" | sed 's/.*# //' 2>/dev/null || echo "no reason")
        printf "  ${RED}%-20s${NC}  %s\n" "$ip" "$comment"
        ((count++))
    done < "$BANFILE"
    echo -e "\n  Total: ${BOLD}$count${NC}"
}

check_ip() {
    if grep -q "deny $1;" "$BANFILE" 2>/dev/null; then
        echo -e "${RED}BANNED${NC}: $(grep "deny $1;" "$BANFILE")"
    else
        echo -e "${GREEN}NOT BANNED${NC}: $1"
    fi
}

auto_ban() {
    # The pipeline and arithmetic below trip `set -e` on legitimate zero-match cases.
    set +euo pipefail

    echo -e "${BOLD}${CYAN}=== AUTO-BAN ===${NC}"
    echo -e "${YELLOW}Threshold: >${AUTO_BAN_THRESHOLD} blocked (403/444) in last ${AUTO_BAN_LOOKBACK} lines${NC}\n"

    local LOGS banned_count=0 sample
    LOGS=$(tail -n "$AUTO_BAN_LOOKBACK" "$LOG_FILE" 2>/dev/null | \
           grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ .+ "([A-Z]+) .+ HTTP' || true)

    # Process substitution, not a pipe — a pipe would run the loop in a subshell
    # and banned_count would always be 0 here.
    while read -r count ip; do
        [[ -z "$ip" ]] && continue
        (( count > AUTO_BAN_THRESHOLD )) || continue
        is_internal "$ip" && continue

        if grep -q "deny $ip;" "$BANFILE" 2>/dev/null; then
            echo -e "  ${YELLOW}SKIP${NC} $ip ($count hits) — already banned"
            continue
        fi

        sample=$(echo "$LOGS" | grep "^$ip " \
                 | awk '{match($0, /"[A-Z]+ ([^ ]+)/, r); print r[1]}' \
                 | head -3 | tr '\n' ',' | sed 's/,$//')

        echo -e "  ${RED}BAN${NC}  $ip — $count hits — tried: $sample"
        echo "deny $ip; # auto-ban: $count blocked, sample: $sample | $(date '+%Y-%m-%d %H:%M')" >> "$BANFILE"
        ((banned_count++))
    done < <(echo "$LOGS" | awk '$9==403 || $9==444' \
             | { [[ -n "$HOME_IP" ]] && grep -v "$HOME_IP" || cat; } \
             | awk '{print $1}' | sort | uniq -c | sort -rn)

    set -euo pipefail

    if (( banned_count > 0 )); then
        echo; reload_nginx
    else
        echo -e "  ${GREEN}No new addresses to ban${NC}"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────

ACTION="${1:-list}"; shift 2>/dev/null || true

case "$ACTION" in
    ban)      ban_ip "${1:?Usage: $0 ban <addr> [reason]}" "${2:-manual ban}" ;;
    unban)    unban_ip "${1:?Usage: $0 unban <addr>}" ;;
    check)    check_ip "${1:?Usage: $0 check <addr>}" ;;
    list)     list_bans ;;
    auto-ban) auto_ban ;;
    *)        echo "Usage: $0 {ban|unban|list|check|auto-ban} [addr] [reason]"; exit 1 ;;
esac
