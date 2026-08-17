# /firewall — Firewall Status & Management

Inspect and manage UFW + iptables rules on x-server and n-server.

**User's request:** $ARGUMENTS

## Architecture

X-server uses a **non-standard firewall setup** — must understand before touching anything:

```
UFW (frontend)
  └── /etc/ufw/before.rules  ← Docker NAT + WireGuard FORWARD rules live HERE
        ├── *nat table (POSTROUTING masquerade for Docker + WireGuard)
        └── FORWARD rules (per-port, not blanket ACCEPT — security hardening)

Docker daemon.json: "iptables": false
  → Docker does NOT manage its own iptables
  → All container routing depends on manual rules in before.rules
```

**NEVER** add Docker or WireGuard rules via `iptables` CLI — they won't persist. Always edit `/etc/ufw/before.rules` then run `sudo ufw reload`.

## X-Server Expected Rules

```
UFW Status: active
Port 80/tcp     → ALLOW IN    Anywhere (nginx)
Port 443/tcp    → ALLOW IN    Anywhere (nginx SSL)  
Port 51820/udp  → ALLOW IN    Anywhere (WireGuard)
Port 2222/tcp   → ALLOW IN    192.168.1.0/24, 10.0.0.0/24 (SSH)
Port 8083/tcp   → ALLOW IN    192.168.1.0/24, 10.0.0.0/24 (ntfy)
Port 445/tcp    → ALLOW IN    192.168.1.0/24, 10.0.0.0/24 (Samba)
```

## N-Server Expected Rules

```
UFW Status: active
Port 2222/tcp  → ALLOW IN    192.168.1.0/24 (SSH)
Port 445/tcp   → ALLOW IN    192.168.1.0/24 (Samba)
Port 139/tcp   → ALLOW IN    192.168.1.0/24 (Samba NetBIOS)
Port 3000/tcp  → ALLOW IN    192.168.1.0/24 (Gitea)
Port 80/tcp    → ALLOW IN    192.168.1.0/24 (Pi-hole)
Port 53        → ALLOW IN    192.168.1.0/24 (DNS)
Port 514/tcp   → ALLOW IN    192.168.1.0/24 (rsyslog)
```

## Common Operations

### Check UFW status (both servers)
```bash
ssh x-server "sudo ufw status verbose"
ssh n-server "sudo ufw status verbose"
```

### Check iptables NAT rules (x-server)
```bash
ssh x-server "sudo iptables -t nat -L -n -v"
```

### Check FORWARD rules (x-server)
```bash
ssh x-server "sudo iptables -L FORWARD -n -v"
```

### View before.rules (x-server)
```bash
ssh x-server "sudo cat /etc/ufw/before.rules"
```

### Flush stale PREROUTING rules (before ufw reload after Docker changes)
```bash
ssh x-server "sudo iptables -t nat -F PREROUTING && sudo ufw reload"
```

### Reload UFW after editing before.rules
```bash
ssh x-server "sudo ufw reload"
```

## Warning

If adding a new DNAT rule for a new container:
1. Pin the container IP with `ipv4_address` in docker-compose.yml first
2. Add PREROUTING + FORWARD rules in `/etc/ufw/before.rules`
3. Flush stale PREROUTING: `sudo iptables -t nat -F PREROUTING`
4. Reload: `sudo ufw reload`
5. Test connectivity

Handle the user's request with this context. For any destructive changes (deleting rules, reloading firewall), show the plan and get confirmation first.
