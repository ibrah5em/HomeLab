# /logs — View & Analyze Server Logs

Fetch and analyze logs from x-server or n-server.

**User's request:** $ARGUMENTS

## Log Sources

### X-Server Logs

| Log | Command |
|---|---|
| nginx access | `ssh x-server "tail -100 ~/docker/nginx/logs/access.log"` |
| nginx error | `ssh x-server "tail -100 ~/docker/nginx/logs/error.log"` |
| nginx watcher alerts | `ssh x-server "sudo journalctl -u nginx-watcher.service --no-pager -n 50"` |
| KidsApp app | `ssh x-server "docker logs --tail 100 kids-app"` |
| ntfy | `ssh x-server "docker logs --tail 50 ntfy"` |
| system journal | `ssh x-server "sudo journalctl --no-pager -n 100"` |
| server-cmd daemon | `ssh x-server "sudo journalctl -u server-cmd.service --no-pager -n 50"` |
| backup last run | `ssh x-server "sudo journalctl -u cron --no-pager --since '24h ago' \| grep backup"` |
| WireGuard | `ssh x-server "sudo journalctl -u wg-quick@wg0 --no-pager -n 30"` |
| AIDE last scan | `ssh x-server "sudo journalctl -u aidecheck.service --no-pager -n 20"` |

### N-Server Logs (x-server logs stored here)

| Log | Command |
|---|---|
| x-server remote syslog | `ssh n-server "sudo ls /var/log/remote/x-server/ && sudo tail -100 /var/log/remote/x-server/syslog"` |
| Gitea | `ssh n-server "sudo journalctl -u gitea --no-pager -n 50"` |
| Pi-hole | `ssh n-server "pihole -t"` (live tail) or `pihole -l` |
| n-server syslog | `ssh n-server "sudo journalctl --no-pager -n 100"` |

## Analysis

When fetching logs, analyze them for:
- **Security events:** repeated 4xx errors, suspicious IPs, scanner signatures (sqlmap, nikto, curl bots)
- **Errors:** 5xx responses, container crashes, OOM events
- **Patterns:** unusual traffic spikes, repeated failed auth attempts

If the user mentions "attack", "scan", or "suspicious", cross-reference the IP with `tool ip-lookup <ip>` for reputation data.

## Common Patterns to Flag

```
# Scanner signatures in nginx logs
"sqlmap" | "nikto" | "masscan" | "zgrab" | ".env" | ".git" | "/wp-" | "/phpmyadmin"

# Auth failures (SSH/Gitea)
"Failed password" | "Invalid user" | "authentication failure"

# Docker OOM
"out of memory" | "OOM" | "killed process"
```

Fetch the relevant logs based on the user's request, then provide a brief analysis with any notable findings highlighted.
