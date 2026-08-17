# /pihole — Pi-hole Management on N-Server

Manage Pi-hole running bare metal on n-server (192.168.1.11, port 53/80).

**User's request:** $ARGUMENTS

## Version & Architecture

- **Pi-hole v6.x** — bare metal (no Docker), Ubuntu 24.04
- **Web UI:** http://192.168.1.11/admin
- **DNS:** port 53 (UDP + TCP), query all LAN devices
- **`systemd-resolved` is DISABLED and MASKED** — prevents port 53 conflicts
- Config: `pihole-FTL --config` (NOT env vars or setupVars.conf from v5)

## Common Operations

### Status & Stats
```bash
ssh n-server "pihole status"
ssh n-server "pihole -c -e"          # query stats today
ssh n-server "pihole -l"             # live log
```

### Block/Allow Domains
```bash
# Block a domain
ssh n-server "pihole blacklist <domain>"

# Unblock (whitelist)
ssh n-server "pihole whitelist <domain>"

# Update gravity (refresh blocklists)
# ⚠️ Needs WARP active (GitHub blocked in Syria)
ssh n-server "sudo pihole -g"
```

### Update Pi-hole
**Always needs Cloudflare WARP** (Pi-hole pulls from GitHub which is blocked):
```bash
ssh n-server
# on n-server:
sudo systemctl stop pihole-FTL
sudo warp-cli connect        # wait ~10s for connection
pihole -up                   # update
sudo warp-cli disconnect
sudo systemctl stop warp-svc
sudo systemctl start pihole-FTL
```

### Restart Pi-hole FTL
```bash
ssh n-server "sudo systemctl restart pihole-FTL"
# If port 53 in use (resolved conflict):
ssh n-server "sudo systemctl stop systemd-resolved 2>/dev/null; sudo systemctl restart pihole-FTL"
```

### Config Changes (v6 syntax)
```bash
# Change setting
ssh n-server "sudo pihole-FTL --config <key> <value>"

# View current config
ssh n-server "sudo pihole-FTL --config"

# Critical: listening mode must be 'all' when using DNAT
ssh n-server "sudo pihole-FTL --config dns.listeningMode all"
```

### Check DNS is Working
```bash
# From WSL — should resolve via n-server
dig @192.168.1.11 google.com

# Query count and block rate
ssh n-server "pihole -c"
```

### Gravity DB (blocklists)
```bash
# Rebuild gravity (update blocklists) - needs WARP
ssh n-server "sudo pihole -g"

# Check gravity DB
ssh n-server "sqlite3 /etc/pihole/gravity.db 'SELECT COUNT(*) FROM gravity;'"

# Clean invalid entries (non-http adlist entries)
ssh n-server "sqlite3 /etc/pihole/gravity.db \"DELETE FROM adlist WHERE address NOT LIKE 'http%'\""
```

## WARP Warning

Cloudflare WARP on n-server:
- Grabs port 53 → **conflicts with Pi-hole**
- Reroutes ALL traffic including SSH → can drop your session
- Always use `tmux` when WARP is active
- **ALWAYS disconnect after use:**
  ```bash
  sudo warp-cli disconnect && sudo systemctl stop warp-svc
  ```

Handle the user's Pi-hole request. For gravity updates or Pi-hole updates, always remind about WARP requirements and port 53 conflicts.
