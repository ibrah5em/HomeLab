#!/bin/bash
# server-health.sh — disk, container and HTTP-liveness checks with push alerts.
#
# Run every 10 minutes from cron:
#   */10 * * * * bash ~/scripts/server-health.sh
#
# Two design decisions worth stealing:
#
#   1. COOLDOWNS. A condition alerts once, then goes quiet for an hour. Without
#      this, a container that won't start buzzes your phone every ten minutes
#      until you mute the channel — and a muted channel is worse than no channel.
#
#   2. ONE-SHOT RECOVERY NOTICES. When a condition clears, you get exactly one
#      "recovered" message and the cooldown resets. You learn the problem is over
#      without having to go and check, and nothing flaps.
#
# Config: edit the CONFIG block, or override via environment.

set -uo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/server-health}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-3600}"

# Containers that should always be running.
EXPECTED_CONTAINERS=(reverse-proxy app-one app-two notifications)

# Public hostnames to probe end-to-end.
CHECK_DOMAINS=(example.com app.example.com)

# Filesystems to watch: "mount:label:threshold%"
CHECK_DISKS=("/:system:85" "/mnt/storage:bulk:85")

# The reverse proxy's address on the container network. With the container
# runtime set to `iptables: false`, published ports don't route via loopback,
# so probe the bridge address directly.
PROXY_IP="${PROXY_IP:-172.18.0.100}"

COMPOSE_FILE="${COMPOSE_FILE:-$HOME/docker/docker-compose.yml}"

mkdir -p "$STATE_DIR"

# ── Helpers ─────────────────────────────────────────────────────────────────

notify() { bash "$SCRIPT_DIR/ntfy-send.sh" "$1" "$2" "${3:-default}" "${4:-}" "${5:-}"; }

# 0 = ok to notify (and stamps the cooldown), 1 = still cooling down.
check_cooldown() {
    local file="$STATE_DIR/$1"
    if [ -f "$file" ]; then
        local last now
        last=$(cat "$file"); now=$(date +%s)
        (( now - last < COOLDOWN_SECONDS )) && return 1
    fi
    date +%s > "$file"
    return 0
}

# Condition cleared: if we had alerted, send one recovery notice and reset.
resolve() {
    local file="$STATE_DIR/$1"
    [ -f "$file" ] || return 0
    rm -f "$file"
    notify "$2" "$3" "default" "white_check_mark"
}

# ── Checks ──────────────────────────────────────────────────────────────────

check_disk() {
    local mount="$1" name="$2" threshold="${3:-85}" usage
    usage=$(df "$mount" --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    [ -z "$usage" ] && return

    if (( usage >= threshold )); then
        check_cooldown "disk-${name}" && {
            local total used avail
            read -r total used avail <<< "$(df -h "$mount" --output=size,used,avail | tail -1 | xargs)"
            notify "Disk Critical: ${name}" \
                   "$(printf '%s is %s%% full\nTotal: %s | Used: %s | Free: %s\nMount: %s' \
                      "$name" "$usage" "$total" "$used" "$avail" "$mount")" \
                   "urgent" "warning,floppy_disk"
        }
    else
        resolve "disk-${name}" "Disk Recovered: ${name}" \
                "${name} is back under ${threshold}% (now ${usage}%)."
    fi
}

check_containers() {
    local container status
    for container in "${EXPECTED_CONTAINERS[@]}"; do
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
        if [ "$status" != "running" ]; then
            check_cooldown "container-${container}" && \
                notify "Container Down: ${container}" \
                       "$(printf '%s is %s\nRun: docker compose -f %s up -d %s' \
                          "$container" "${status:-not found}" "$COMPOSE_FILE" "$container")" \
                       "urgent" "skull,whale" "restart:${container}"
        else
            resolve "container-${container}" "Container Recovered: ${container}" \
                    "${container} is running again."
        fi
    done
}

# Catches "the container is 'running' but the app is wedged" — which a status
# check alone misses entirely. Probes the full proxy→app path with correct SNI
# and Host so the proxy routes to the right vhost.
# Healthy = any 2xx/3xx/4xx (both proxy and app answered). Down = no response or 5xx.
check_http() {
    local domain="$1" code
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 \
           --resolve "${domain}:443:${PROXY_IP}" "https://${domain}/" 2>/dev/null)

    if [ -z "$code" ] || [ "$code" = "000" ] || { [ "$code" -ge 500 ] 2>/dev/null; }; then
        check_cooldown "http-${domain}" && \
            notify "Site Down: ${domain}" \
                   "$(printf '%s returned %s through the proxy.\nThe container may be running while the app is not serving — check app logs.' \
                      "$domain" "${code:-no response}")" \
                   "urgent" "warning,globe_with_meridians"
    else
        resolve "http-${domain}" "Site Recovered: ${domain}" \
                "${domain} is serving again (HTTP ${code})."
    fi
}

# ── Run ─────────────────────────────────────────────────────────────────────

for spec in "${CHECK_DISKS[@]}"; do
    IFS=: read -r mount label threshold <<< "$spec"
    check_disk "$mount" "$label" "$threshold"
done

check_containers

for domain in "${CHECK_DOMAINS[@]}"; do
    check_http "$domain"
done
