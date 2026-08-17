# /ntfy — ntfy Notification Management

Manage ntfy push notification service on x-server, and send notifications.

**User's request:** $ARGUMENTS

## Architecture

- **Container:** `ntfy` in Docker, network `docker_management`
- **LAN access:** http://192.168.1.10:8083 (LAN + VPN only)
- **WAN access:** https://site.example.net/ntfy (via nginx reverse proxy)
- **Config:** `~/docker/ntfy/server.yml`
- **Credentials:** `~/docker/ntfy/.env` (auth token, bearer token)
- **Auth DB:** `/var/cache/ntfy/user.db` inside container

## Send a Notification

```bash
# Quick send (from WSL, LAN)
curl -H "Authorization: Bearer <token>" \
  -d "<message>" \
  http://192.168.1.10:8083/<topic>

# From anywhere (WAN via nginx)
curl -H "Authorization: Bearer <token>" \
  -d "<message>" \
  https://site.example.net/ntfy/<topic>
```

## Common Topics (from server-cmd.py)

| Topic | Purpose |
|---|---|
| `x-server-alerts` | nginx watcher alerts (scanners, DDoS) |
| `x-server-cmd` | ChatOps commands → server |
| `x-server-status` | Server status updates |

## Service Management

```bash
# Status
ssh x-server "docker logs --tail 50 ntfy"
ssh x-server "docker ps | grep ntfy"

# Restart
ssh x-server "cd ~/docker && docker compose restart ntfy"

# View config
ssh x-server "cat ~/docker/ntfy/server.yml"
```

## ntfy Config Notes

- `behind-proxy: true` required — without it, ntfy sees nginx's IP instead of real clients
- `auth-file` path must exist inside the container — uses a mounted volume path
- WebSocket reverse proxy needs the `map $http_upgrade $connection_upgrade` pattern in nginx (NOT hardcoded `Connection "upgrade"`)
- ntfy WebSocket path and HTTP path share the same nginx location block

## server-cmd Daemon

The `server-cmd.service` on x-server subscribes to ntfy topics and executes commands:

```bash
# Check daemon status
ssh x-server "sudo systemctl status server-cmd.service"

# View daemon logs
ssh x-server "sudo journalctl -u server-cmd.service --no-pager -n 30"

# Restart daemon
ssh x-server "sudo systemctl restart server-cmd.service"
```

Handle the user's ntfy request. For sending alerts or notifications, use the LAN endpoint when on the same network, WAN endpoint otherwise.
