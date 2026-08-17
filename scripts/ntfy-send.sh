#!/bin/bash
# ntfy-send.sh — send a push notification via a self-hosted ntfy server.
#
# Usage: ntfy-send.sh "Title" "Message body" [priority] [tags] [action]
#   priority: min | low | default | high | urgent   (default: default)
#   tags:     comma-separated emoji tags, e.g. "warning,skull"
#   action:   optional one-tap button:
#               ban:<ip>        → publishes "ban <ip> exploit-hit" to the command topic
#               restart:<name>  → publishes "restart <name>" to the command topic
#
# The action button uses a SEPARATE, publish-only token scoped to the command
# topic — never the admin token. That way a notification sitting on a lock
# screen cannot be used to read your alert history. If that token is unset the
# button is silently omitted and the notification still sends.
#
# Config: copy ntfy.env.example to ~/.config/ntfy-token.env (chmod 600) and set
#   NTFY_TOKEN=...       # publish rights on the alert topic
#   NTFY_CMD_TOKEN=...   # publish-only, command topic only

set -uo pipefail

NTFY_URL="${NTFY_URL:-http://127.0.0.1:8080}"
NTFY_TOPIC="${NTFY_TOPIC:-security-alerts}"
NTFY_CMD_TOPIC="${NTFY_CMD_TOPIC:-server-cmd}"
NTFY_ENV="${NTFY_ENV:-$HOME/.config/ntfy-token.env}"

# shellcheck source=/dev/null
[ -r "$NTFY_ENV" ] && source "$NTFY_ENV"

if [ -z "${NTFY_TOKEN:-}" ]; then
    echo "ntfy-send: NTFY_TOKEN unset (looked in $NTFY_ENV)" >&2
    exit 1
fi

TITLE="${1:?Usage: ntfy-send TITLE MESSAGE [PRIORITY] [TAGS] [ACTION]}"
MESSAGE="${2:?Usage: ntfy-send TITLE MESSAGE [PRIORITY] [TAGS] [ACTION]}"
PRIORITY="${3:-default}"
TAGS="${4:-}"
ACTION="${5:-}"

HEADERS=(
    -H "Title: ${TITLE}"
    -H "Priority: ${PRIORITY}"
    -H "Authorization: Bearer ${NTFY_TOKEN}"
)
[ -n "$TAGS" ] && HEADERS+=(-H "Tags: ${TAGS}")

# One-tap action button. Reuses the verbs the ChatOps listener already parses,
# so there's one command vocabulary rather than two.
if [ -n "$ACTION" ] && [ -n "${NTFY_CMD_TOKEN:-}" ]; then
    kind="${ACTION%%:*}"
    arg="${ACTION#*:}"
    case "$kind" in
        ban)     body="ban ${arg} exploit-hit" ; label="Ban ${arg}"     ;;
        restart) body="restart ${arg}"         ; label="Restart ${arg}" ;;
        *)       body=""                       ; label=""              ;;
    esac
    if [ -n "$body" ]; then
        HEADERS+=(-H "Actions: http, ${label}, ${NTFY_URL}/${NTFY_CMD_TOPIC}, method=POST, headers.Authorization=Bearer ${NTFY_CMD_TOKEN}, body=${body}, clear=true")
    fi
fi

curl -s -o /dev/null -w "%{http_code}" \
    "${HEADERS[@]}" \
    -d "${MESSAGE}" \
    "${NTFY_URL}/${NTFY_TOPIC}"
