# /status — Full Lab Health Check

Run a comprehensive health check across both servers and report the results.

Execute the following checks in parallel using SSH, then present a unified status dashboard.

## X-SERVER (192.168.1.10)

SSH command: `ssh x-server`

Check and report:
1. **System** — uptime, load average, RAM usage (`free -m`), disk usage (`df -h /` and `/mnt/storage`)
2. **Docker containers** — `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"` (flag any not Up)
3. **nginx** — `docker compose -f ~/docker/docker-compose.yml exec nginx nginx -t` (config validity)
4. **SSL certs** — check expiry for `site.example.net` and `kids.example.net` via `openssl s_client`
5. **WireGuard** — `sudo wg show` (peer count only — no recent handshake is normal, peers are personal devices)
6. **UFW** — `sudo ufw status` (confirm expected rules are active)
7. **Backup** — check timestamp of last backup: `ls -lt /mnt/storage/backup/ | head -5`
8. **AIDE** — last run from journal: `sudo journalctl -u dailyaidecheck.service --no-pager -n 3` (silent = clean, no changes)
9. **Recent alerts** — `sudo journalctl -u nginx-watcher.service --no-pager -n 5` (Attack Payload alerts are normal internet noise — only flag if other alert types appear)

## N-SERVER (192.168.1.11)

SSH command: `ssh n-server`

Check and report:
1. **System** — uptime, load, RAM, disk (`df -h /`)
2. **Pi-hole** — `pihole status` (FTL listening + blocking enabled)
3. **Gitea** — `sudo systemctl is-active gitea`
4. **Samba** — `sudo systemctl is-active smbd`
5. **rsyslog receiver** — `sudo systemctl is-active rsyslog`
6. **UFW** — `sudo ufw status`
7. **Recent x-server logs** — `sudo ls -lt /var/log/remote/x-server/ | head -5`

## Output Format

Present results as a clean dashboard with:
- ✅ for healthy, ⚠️ for warnings, ❌ for failures
- A summary line at the top: "X-server: N/9 OK | N-server: N/7 OK"
- Highlight anything that needs attention
- If a server is unreachable, say so clearly and suggest checking if it's powered on
