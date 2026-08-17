# /vpn — WireGuard VPN Management

Manage WireGuard VPN on x-server (native, non-Docker).

**User's request:** $ARGUMENTS

## Architecture

- **Interface:** `wg0` on x-server host (10.0.0.1)
- **Subnet:** 10.0.0.0/24
- **Port:** 51820/udp (public)
- **Endpoint:** <WAN-IP>:51820
- **Config:** `/etc/wireguard/wg0.conf`
- **Peers config:** `/etc/wireguard/peers/` (one file per client)

WireGuard is native on the HOST (not in Docker) because `iptables: false` makes Docker VPN networking painful.

## Key Facts

- **Masquerade rule** in `/etc/ufw/before.rules`: makes VPN traffic appear as x-server's LAN IP to other devices
- **FORWARD rules** also in `before.rules` — not just masquerade alone
- **SSH listens on 10.0.0.1** — VPN clients can SSH to x-server over VPN
- **One key pair per client** — never reuse; revoke by removing `[Peer]` block
- **Split tunnel** — only routes LAN (192.168.1.0/24) through VPN, not all traffic
- **Port scanners** see port 51820 as closed (WireGuard silently drops unauthenticated packets)

## Common Operations

### Check VPN status
```bash
ssh x-server "sudo wg show"
```
Shows: peer count, latest handshakes, bytes sent/received, allowed IPs.

### View config
```bash
ssh x-server "sudo cat /etc/wireguard/wg0.conf"
```

### Start / Stop / Restart
```bash
ssh x-server "sudo systemctl start wg-quick@wg0"
ssh x-server "sudo systemctl stop wg-quick@wg0"
ssh x-server "sudo systemctl restart wg-quick@wg0"
ssh x-server "sudo systemctl status wg-quick@wg0"
```

### Add a new client
1. Generate key pair **on x-server**:
   ```bash
   wg genkey | tee /etc/wireguard/peers/<name>-private.key | wg pubkey > /etc/wireguard/peers/<name>-public.key
   ```
2. Assign next available IP (10.0.0.2, .3, etc.)
3. Add `[Peer]` block to `/etc/wireguard/wg0.conf`:
   ```ini
   [Peer]
   # <name> — <device description>
   PublicKey = <client-public-key>
   AllowedIPs = 10.0.0.<N>/32
   ```
4. Hot-reload: `sudo wg addconf wg0 /dev/stdin <<< "[Peer]..."` or `sudo systemctl restart wg-quick@wg0`
5. Create client config file and share it securely

### Revoke a client
Remove their `[Peer]` block from `/etc/wireguard/wg0.conf` then restart.

### Client config template
```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.<N>/24
DNS = 192.168.1.11  # n-server Pi-hole

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <WAN-IP>:51820
AllowedIPs = 192.168.1.0/24, 10.0.0.0/24  # split tunnel — LAN only
PersistentKeepalive = 25
```

### Check WoL keepalive
```bash
# WoL re-apply service (NIC loses config on boot)
ssh x-server "sudo systemctl status wol-enable.service"
```

Handle the user's VPN request. For adding new peers, generate key pairs on the server side and never expose private keys in chat.
