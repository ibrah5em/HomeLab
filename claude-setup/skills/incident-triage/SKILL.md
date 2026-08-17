---
name: incident-triage
description: >
  Use this skill whenever the operator reports an alert, a strange ntfy notification, a
  spike on the daily summary, an AIDE diff, a service that went down, or any "what
  just happened" investigation that needs cross-server correlation. Triggers on
  "got an alert", "what's this notification", "investigate this", "triage X",
  "something looks off on x-server", "check why <service> alerted", AIDE/nginx-watcher
  /server-health alarms, or pasted ntfy message bodies.
---

# incident-triage — Structured Triage for Home Lab Alerts

When an alert fires (or the operator sees something odd), this skill drives the investigation
from raw signal → corroborated evidence → minimal response. The goal is fast, evidence-based
answers, not speculation from CLAUDE.md.

## Step 1 — Capture the Signal

Get the alert text from the operator verbatim (the ntfy notification body, the AIDE diff line,
the log snippet — whatever triggered the concern). Pull out:

- **Source** — which topic / service / cron job. Map it using the monitoring agent's table:
  `security-alerts` → could be nginx-watcher, server-health, daily-summary, ban-ip,
  SSL renew, or any `ntfy-send.sh` call.
- **Timestamp** — convert to UTC if the operator quoted local time. Pin a ±10 minute window.
- **Specifics** — IP, domain, file path, service name, error code. Whatever the alert names,
  use it as the next-step search key.

If the operator just says "I got an alert" with no detail, ask him to paste the body before
running commands. Don't blind-grep the logs.

## Step 2 — Confirm the Source (Don't Trust the Title)

ntfy alert titles can be misleading after wrapper-script changes. Confirm what actually
sent it:

```bash
# What recently called ntfy-send.sh?
ssh x-server "journalctl --since='30 min ago' | grep -iE 'ntfy|nginx-watcher|server-cmd|aide' | tail -40"

# Which cron job ran around that time?
ssh x-server "grep CRON /var/log/syslog 2>/dev/null | grep -E '$(date -u -d '@'$((`date +%s` - 1800)) '+%H:[0-5][0-9]')' | tail"
```

If the alert came from cron, identify the exact script in `~/scripts/`. Read that script
to know what condition it tripped on (don't guess from the title).

## Step 3 — Pull Corroborating Evidence

Run these in parallel where possible. Adjust the window from Step 1.

### x-server side (live signal)

```bash
# nginx access/error around the window
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx \
  sh -c 'tail -200 /var/log/nginx/access.log; echo ---; tail -100 /var/log/nginx/error.log'"

# Which containers were healthy?
ssh x-server "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# Service health snapshot
ssh x-server "systemctl --failed; echo ---; uptime; echo ---; df -h /"
```

### n-server side (archive — survives x-server reboot)

```bash
# Forwarded x-server logs around the window
nsudo grep -h "$(date -u -d '<TIMESTAMP>' '+%b %_d %H:')" /var/log/remote/x-server/*.log | head -100

# nginx-watcher's history (its journald lines are forwarded)
nsudo tail -200 /var/log/remote/x-server/python3.log 2>/dev/null
```

### nginx-watcher / server-cmd specifically

```bash
ssh x-server "journalctl -u nginx-watcher --since='1 hour ago' --no-pager | tail -60"
ssh x-server "journalctl -u server-cmd --since='1 hour ago' --no-pager | tail -60"
```

### AIDE-specific

```bash
ssh x-server "sudo -S cat /var/lib/aide/aide.log 2>/dev/null | tail -80" <<< "$X_SERVER_SUDO"
# Or use the wrapper:
ssh x-server "bash ~/scripts/aide-check.sh"
```

## Step 4 — Classify

Match what you found against the known-non-issue list in memory before escalating:

- [[xserver_known_non_issues]] — power-watchdog noise, expected attack alerts, idle
  WireGuard peers. Don't mistake these for novel incidents.
- Recurring scan/probe IPs that `ban-ip.sh` already handles → noise, not incident.
- AIDE diffs on logs/cache/tmp paths → expected churn, not tampering.

Bucket the incident as ONE of:
- **Noise** — known pattern, no action. Note it and stop.
- **Operational** — service degraded but not malicious (disk full, container crash-loop,
  cert near expiry). Propose a fix.
- **Security-relevant** — unexpected access pattern, AIDE diff on a sensitive path,
  unfamiliar IP succeeding (not just probing). Move to Step 5 carefully.

## Step 5 — Propose a Response

Show the operator the smallest correct action first. Examples by bucket:

- **Disk full** → `docker system df`, identify the bloat, propose `docker system prune` or
  log rotation — but confirm before running prune (it's destructive to dangling images).
- **Container crash-loop** → `docker logs --tail 200 <name>`, name the error, propose fix.
- **Unauthorized access attempt** → check `ban-ip.sh` whitelist, confirm IP is banned;
  if not, propose adding it. Never preemptively block an IP that hasn't actually attacked.
- **Cert expiry** → run the certbot renew incantation from
  `.claude/skills/new-service/references/certbot.md` (force-renewal for the specific cert).
- **AIDE diff on system binary** → STOP. Show the exact path + hash diff to the operator. Do
  not update the AIDE baseline. This is a real-investigate scenario.

## Step 6 — Document

If the incident was novel (not in [[xserver_known_non_issues]]) and resolved, save a memory
entry:

- **Feedback memory** if the operator corrected the response approach
- **Project memory** if it's an ongoing situation (e.g. "ISP is throttling port 443 between
  19:00–22:00 UTC, alerts that fire in that window are likely false positives")

If it's a recurring false-positive, propose adding it to the known-non-issues memory.

## Output

Present:
1. **Headline** — one sentence: source, severity bucket, root cause.
2. **Evidence** — 3–6 quoted log lines that prove the headline. Reference file paths.
3. **Proposed action** — explicit commands, with destructive ones flagged for confirmation.
4. **Follow-up** — anything worth watching for the next 24 hours, or a memory update if novel.

Keep it tight. the operator is usually triaging on mobile after the ntfy ping — short is kind.
