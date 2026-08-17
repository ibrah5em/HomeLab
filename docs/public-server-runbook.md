# Public server — full runbook

> **Sanitized for publication.** This is the real operational runbook, with
> identifying values substituted: public addresses, hostnames, MAC addresses and
> account names are placeholders, and paths are genericized. Internal RFC1918
> addresses are kept — they're meaningless to a reader and the topology is the
> point. Third-party project names are replaced with placeholders.
>
> Both machines were decommissioned in August 2026. Nothing described here is running.


> Last updated: August 17, 2026


## 📊 HARDWARE & SYSTEM

**Server Hardware:**
- HP G62 laptop (Intel i3 M330 @ 2.13GHz, 5.6GiB RAM)
- 224GB SSD (sda) — Ubuntu Server 22.04 LTS (100GB LVM partition, ~120GB unallocated)
- 298GB HDD (sdb) — mounted at `/mnt/storage`
- NIC: enp3s0, MAC `<MAC>` (WoL enabled but NIC loses standby power on shutdown)
- Battery: BAT0 (aging, unreliable for long outages)
- Location: Near router, headless (no monitor)

---

## 🌐 NETWORK CONFIGURATION

**Local Network:**
- **Hostname:** x-server
- **Ethernet IP:** 192.168.1.10 (static, primary)
- **WiFi:** Not available (adapter not detected)
- **Router:** <router-model>
- **Router DHCP range:** 192.168.1.120–200
- **Router DHCP DNS:** Set to N-server (Pi-hole moved off X-server — April 12, 2026)
- **Static IP:** Ethernet reserved in router

**Public Internet:**
- **Static IP:** <WAN-IP>
- **Domain:** site.example.net (DuckDNS, free)
- **HTTPS:** Let's Encrypt certificate (auto-renews every Sunday 3 AM)
- **Port forwarding:** 80 → 192.168.1.10:80, 443 → 192.168.1.10:443, 51820/udp → 192.168.1.10:51820
- **DMZ:** Disabled

**VPN (WireGuard):**
- **Interface:** wg0
- **VPN subnet:** 10.0.0.0/24
- **Server IP:** 10.0.0.1
- **Port:** 51820/udp
- **Endpoint:** <WAN-IP>:51820

---

## 🔒 SECURITY CONFIGURATION

### SSH
- **Port:** 2222 (changed from 22)
- **Bound to:** 192.168.1.10 + 10.0.0.1 (LAN + VPN only, not accessible from internet)
- **Authentication:** SSH keys only (passwords disabled)
- **Key type:** Ed25519 (`x-server-new`)
- **Root login:** Disabled
- **User:** homelab
- **Connection:** `ssh x-server` (via SSH config)
- **Old key:** Revoked and deleted (was compromised in terminal history)

**Laptop SSH config (`~/.ssh/config`):**
```
Host x-server
    HostName 192.168.1.10
    User homelab
    Port 2222
    IdentityFile ~/.ssh/x-server-new
    ServerAliveInterval 60

Host *
    ServerAliveInterval 60
```

### Firewall (UFW)
Only ports 80, 443, and 51820 are open to the public internet. Everything else is LAN-only or VPN-only.

| Port      | Service         | Access                        |
| --------- | --------------- | ----------------------------- |
| 80/tcp    | HTTP (Nginx)    | 🌍 Public                     |
| 443/tcp   | HTTPS (Nginx)   | 🌍 Public                     |
| 51820/udp | WireGuard VPN   | 🌍 Public                     |
| 2222/tcp  | SSH             | 🏠 LAN + 🔒 VPN               |
| 8083/tcp  | ntfy            | 🏠 LAN + 🔒 VPN               |
| 445/tcp   | Samba SMB       | 🏠 LAN + 🔒 VPN (hosts allow restricts to 192.168.1.0/24 + 10.0.0.0/24) |
| 139/tcp   | Samba NetBIOS   | 🏠 LAN only                   |
| 137/udp   | Samba NetBIOS   | 🏠 LAN only                   |
| 138/udp   | Samba NetBIOS   | 🏠 LAN only                   |

### Docker Network Isolation
⚠️ Docker bypasses UFW by default. This has been fixed:

**`/etc/docker/daemon.json`:**
```json
{
    "dns": ["8.8.8.8", "1.1.1.1"],
    "iptables": false
}
```

With `"iptables": false`, Docker no longer manipulates iptables directly. All traffic goes through UFW rules.

⚠️ **Critical:** With `"iptables": false`, Docker containers lose outbound internet access because NAT and FORWARD rules are not created. Manual rules have been added to `/etc/ufw/before.rules`:

**NAT block (before `*filter`):**
```
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.18.0.0/16 ! -o br-management -j MASQUERADE
-A PREROUTING -i enp3s0 -p tcp --dport 80 -j DNAT --to-destination 172.18.0.100:80
-A PREROUTING -i enp3s0 -p tcp --dport 443 -j DNAT --to-destination 172.18.0.100:443
COMMIT
```

**Forward rules (before final `COMMIT` in `*filter`):**
```
-A ufw-before-forward -i wg0 -o enp3s0 -j ACCEPT
-A ufw-before-forward -i enp3s0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-forward -i enp3s0 -o br-management -p tcp -d 172.18.0.100 --dport 80 -j ACCEPT
-A ufw-before-forward -i enp3s0 -o br-management -p tcp -d 172.18.0.100 --dport 443 -j ACCEPT
-A ufw-before-forward -i br-management -o enp3s0 -p udp --dport 53 -j ACCEPT
-A ufw-before-forward -i br-management -o enp3s0 -p tcp --dport 53 -j ACCEPT
-A ufw-before-forward -i br-management -o enp3s0 -p tcp --dport 80 -j ACCEPT
-A ufw-before-forward -i br-management -o enp3s0 -p tcp --dport 443 -j ACCEPT
```

Container outbound is restricted to DNS (53), HTTP (80), and HTTPS (443) only. Return traffic is handled by the global `RELATED,ESTABLISHED` rule in the `*filter` chain. The old blanket `ACCEPT ALL` rule for `br-management → enp3s0` has been removed — if a container is compromised, the attacker cannot use arbitrary outbound ports (no reverse shells, no SSH tunneling, no exfil on custom ports).

The bridge interface `br-management` is a stable name set via `driver_opts` in docker-compose.yml — it survives network recreation (`docker compose down && up`). The DNAT rules route external traffic on ports 80/443 directly to nginx's container IP (`172.18.0.100`), bypassing Docker's userland proxy. This preserves real client IPs in nginx logs — no more `172.18.0.1`.

⚠️ **If nginx's static IP (`172.18.0.100`) changes** in docker-compose.yml, the DNAT and FORWARD rules in `/etc/ufw/before.rules` must be updated to match.

### Nginx Security (Grade A — securityheaders.com)
- **Rate limiting:** 10 requests/sec per IP, burst up to 20 (now uses real client IPs via DNAT)
- **SSL:** TLS 1.2/1.3 only, strong ciphers, server preference
- **HSTS:** Strict-Transport-Security enabled (1 year)
- **CSP:** Content-Security-Policy restricting resource origins — main site allows `fonts.googleapis.com` / `fonts.gstatic.com` (Google Fonts); friend sites have stricter CSP (no external CDNs)
- **Headers:** X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy, Permissions-Policy
- **Version hiding:** `server_tokens off`
- **Bot blocking:** `map`-based UA filtering — sqlmap, nikto, nmap, masscan, zgrab, ffuf, gobuster, dirbuster, wfuzz, leakix, censys, bitsight, scrapy, python-requests, Go-http-client, libwww-perl, QIHU, shellshock patterns
- **Query string filtering:** `map`-based — blocks SQL injection (UNION SELECT, concat_ws, information_schema, sleep, benchmark), path traversal (../, %252f, %09..), XDEBUG, SSTI ({{}}), XSS (<script, javascript:), env probes (.env, env.php, passwd, etc/shadow, proc/self), DNS-over-HTTPS (dns=)
- **URI path filtering:** `map`-based — blocks .env, .git, .svn, .htaccess, wp-admin/login/content/includes, xmlrpc.php, phpunit, phpmyadmin, cgi-bin, .php/.asp/.aspx/.jsp, config files, .sql/.bak/.old/.orig/.swp, shell, eval-stdin
- **IP banning:** `banned-ips.conf` included in all server blocks — managed via `ban-ip.sh`, with hourly auto-ban via cron
- **Method restriction:** Only GET and HEAD allowed (static site — no POST/PUT/DELETE)
- **Default catch-all server:** Direct IP access and unknown Host headers return 444 (connection dropped)
- **Real IP logging:** DNAT rules in `/etc/ufw/before.rules` route traffic directly to nginx on Docker bridge, bypassing Docker proxy — nginx sees actual client IPs
- **Persistent logs:** Nginx access/error logs written to `~/docker/nginx-logs/` (mounted volume), survive container restarts — rotated weekly, 4 weeks retained
- **MIME types:** `include /etc/nginx/mime.types` — required for correct CSS/JS serving

### Other Security
- ✅ Fail2ban (3 failed attempts = 1 hour ban on SSH)
- ✅ Automatic security updates enabled
- ✅ Lid-closed = server stays running
- ✅ Samba (SMB) — LAN + VPN (single `files` share at `/mnt/storage/files`, hosts allow restricts to 192.168.1.0/24 + 10.0.0.0/24, port never forwarded publicly, two-layer defense: UFW + hosts allow)
- ✅ Cockpit — disabled
- ✅ All Docker services bound to 192.168.1.10 (not 0.0.0.0)
- ✅ Strong passwords (32-char) on all services
- ✅ nginx-watcher — breach detection via ntfy (alerts only when an exploit path returns 2xx — see Monitoring); scan/attack volume is batched into the daily summary, not pushed
- ✅ login-watcher — alerts on external-source SSH logins and unexpected sudo (journald follower, `login-watcher.service`)
- ✅ WireGuard VPN — key-based auth, silent to port scans, full LAN access via masquerade
- ✅ Sudoers (`/etc/sudoers.d/server-cmd`) — passwordless sudo for `wg show`, `systemctl hibernate`, `systemctl restart nginx-watcher` only (used by server-cmd remote management)
- ✅ ntfy token centralized — stored in `~/.config/ntfy-token.env` (mode 600), loaded via `EnvironmentFile` in systemd services and `source` in shell scripts. Removed from all script source code (April 14, 2026)
- ✅ Script permissions hardened — `server-cmd.py`, `nginx-watcher.py`, `ntfy-send.sh` set to mode 700 (owner-only) (April 14, 2026)
- ✅ AIDE file integrity monitoring — daily check at 3:30 AM, monitors SSH/UFW/Docker/WireGuard/sudoers/systemd/scripts/PAM/crontabs, alerts via ntfy on changes (April 14, 2026)
- ✅ Syslog forwarding — rsyslog forwards all logs to n-server (192.168.1.11:514 TCP), stored in `/var/log/remote/x-server/` per program, 8-week rotation. Off-box forensic copy survives local log deletion (April 14, 2026)
- ✅ Docker container outbound restricted — FORWARD rules limited to DNS (53), HTTP (80), HTTPS (443) only. No arbitrary outbound ports (April 14, 2026)
- ✅ Stale credentials removed — `/root/.backup-secrets` deleted (MariaDB removed March 2026) (April 14, 2026)

### Power Management (Hibernate on Power Loss)

The server runs on an HP G62 laptop with an aging battery. Syria has frequent power outages (solar + grid), so the server uses hibernate to survive extended outages without data loss.

**Strategy:**
- **Short outage:** Battery keeps server running — no interruption
- **Long outage:** Battery hits 15% → clean hibernate (state saved to disk, zero power drain) → RTC alarm wakes server every 30 min → checks if AC is back → if yes, resumes; if not, hibernates again
- **Fully automatic — zero button presses required**

**Setup:**
- Swap file: `/swap.img` (6GB, must be ≥ RAM for hibernate)
- GRUB: `resume=/dev/mapper/ubuntu--vg-ubuntu--lv resume_offset=20756480`
- Wake-on-LAN: Enabled (`ethtool -s enp3s0 wol g`) but NIC loses standby power on this hardware — WoL from shutdown does not work
- RTC wake: `rtcwake -m disk` works — used for periodic wake-and-check cycle
- Power watchdog: `power-watchdog.service` monitors `ACAD/online` and `BAT0/capacity`

**Power supply paths:**
```
/sys/class/power_supply/ACAD/online    → 1 (charger connected) / 0 (disconnected)
/sys/class/power_supply/BAT0/capacity  → 0-100 (battery percentage)
/sys/class/power_supply/BAT0/status    → Charging / Discharging / Full
```

**Systemd services:**
- `wol.service` — oneshot, re-enables WoL on every boot (`ethtool -s enp3s0 wol g`)
- `power-watchdog.service` — daemon, monitors AC/battery state, hibernates and wakes via rtcwake

**Notifications (via ntfy):**
- ⚡ AC Power Lost — when charger disconnects
- ✅ AC Power Restored — when charger reconnects (if battery survived)
- 🔴 Battery Critical — when battery hits 15%, hibernating with 30-min wake cycle
- ✅ Server Resumed — when AC returns during wake cycle

---

## 🐳 DOCKER SERVICES

All services managed via: `~/docker/docker-compose.yml`

### Running Containers

| Container | Port | Network | Purpose |
|-----------|------|---------|---------|
| **Nginx** | 80, 443 (via DNAT, no Docker port publishing) | Public | Web server + reverse proxy |
| **ntfy** | 8083 (LAN) + 443 via nginx reverse proxy | LAN + Public | Push notifications (security alerts, server health, daily summary) |
| **kids-app** | 3000 (internal only, proxied via nginx) | Public (via nginx) | KidsApp — children's educational platform (a separate project, not mine) |
| **tasks**    | 80 (internal only, proxied via nginx)   | Public (via nginx) | Simple Task Manager — Laravel + php-fpm + internal nginx, SQLite. Image from `ghcr.io/<user>/tasks:latest`, auto-rolled by Watchtower |
| **portfolio** | 80 (internal only, proxied via nginx) | Public (via nginx) | Personal portfolio — static HTML/CSS/JS on nginx:alpine. Image from `ghcr.io/<user>/portfolio:latest`, auto-rolled by Watchtower. **Warm standby since 2026-08-08** — `example.com` moved to Cloudflare Workers; this container now serves only `site.example.net` and exists as the rollback path |
| **watchtower** | —                                  | Internal (docker_management) | Label-scoped image roller. Pulls new GHCR digests and recreates opted-in containers (`tasks`, `portfolio`) |

### Removed Containers

| Container | Reason |
|-----------|--------|
| **Pi-hole** | Moved to N-server — removed April 12, 2026 |
| **Homer** | Unused — removed April 12, 2026 |
| **Nextcloud** | Replaced by Samba — too heavy for i3 M330 (3 containers, 596MB RAM) — removed March 29, 2026 |
| **MariaDB** | Nextcloud dependency — removed March 29, 2026 |
| **Redis** | Nextcloud cache — removed March 29, 2026 |
| **Filebrowser** | Unused — removed March 14, 2026 |
| **Portainer** | Unused, CLI preferred — removed March 16, 2026 |
| **Uptime Kuma** | Unnecessary for home server — removed March 16, 2026 |
| **telegram-bot** | `api.telegram.org` blocked in Syria — removed March 8, 2026 |
| **ttyd** | Crash-looping (exit 127) — removed March 8, 2026 |
| **Syncthing** | Never used — removed March 8, 2026 |

### Service Details

**Nginx (Public Web Server)**
- ~~Portfolio at `https://example.com`~~ — **the `.me` + `www` vhosts are stale as of 2026-08-08.** DNS now points at Cloudflare, so these server blocks receive no traffic. Left in place deliberately (rollback path) until the server role swap is settled; delete them then, along with the certbot `-d` entries.
- Portfolio at `https://site.example.net` — reverse-proxies to the `portfolio` container (`172.18.0.92:80`). Sets `Link: <https://example.com/...>; rel="canonical"` **and** `X-Robots-Tag: noindex, nofollow` (added 2026-05-24) so search engines drop it from the index and SEO consolidates on `.me`. Both still correct after the Cloudflare move — the canonical target is simply served by Cloudflare now, not by this box.
- ntfy reverse proxy at `https://ntfy.example.net` (WebSocket/SSE, 24h timeouts)
- KidsApp reverse proxy at `https://kids.example.net` → `172.18.0.90:3000`
- Simple Task Manager reverse proxy at `https://tasks.example.net` → `172.18.0.91:80`
- HTTP → HTTPS redirect
- Let's Encrypt certificates (auto-renewal via cron)
- HTTP/2 enabled on portfolio vhosts (`.me` + duckdns) for parallel asset loading / better Core Web Vitals
- Gzip enabled globally (`http {}` block) — text/css/js/svg/fonts/json compressed at level 6
- Static-asset caching on portfolio vhosts: images/fonts `max-age=30d immutable`, css/js `max-age=7d`. Upstream `Cache-Control`/`Expires` hidden via `proxy_hide_header` so the outer nginx is the single source of truth.
- Security headers: Grade A
- Rate limiting enabled (uses real client IPs)
- Hardened: map-based UA/query string/URI filtering, method restriction, default catch-all (444)
- No Docker port publishing — traffic routed via DNAT rules in `/etc/ufw/before.rules`
- Static IP: `172.18.0.100` on `docker_management` network
- Config: `~/docker/nginx.conf`
- Banned IPs: `~/docker/banned-ips.conf`
- Access logs: `~/docker/nginx-logs/access.log`
- Add new sites: `bash ~/scripts/add-site.sh <domain>`

**Samba (LAN + VPN File Sharing)**
- Config: `/etc/samba/smb.conf`
- Bound to: all interfaces (`bind interfaces only` removed — Samba doesn't bind to WireGuard interfaces reliably)
- Access restricted to: `192.168.1.0/24` and `10.0.0.0/24` via `hosts allow` + UFW (port 445 never forwarded publicly)
- Shares:
  - `[files]` → `/mnt/storage/files` (read/write)
- User: `homelab` (Samba password separate from Linux password)
- Access (LAN): `\\192.168.1.10\files`
- Access (VPN): `\\10.0.0.1\files`
- The old `[home]` share (`/home/homelab`) was removed 2026-05-24 — exposing all of `~` leaked secrets (`.ssh/`, `.server-creds.env`, `.git-credentials`, every `~/docker/**/.env`) to anyone with the Samba password. SSH in for config edits instead.

**ntfy (Push Notifications)**
- Self-hosted push notification server
- Docker network: `docker_management` (bridge: `br-management`)
- Static IP: `172.18.0.83` on `docker_management` network
- Port: `192.168.1.10:8083:80` (LAN direct) + reverse-proxied via nginx on 443
- Public URL: `https://ntfy.example.net` (nginx reverse proxy with WebSocket/SSE support)
- Config: `~/docker/ntfy/etc/server.yml`
- Cache: `~/docker/ntfy/cache/`
- Auth DB: `~/docker/ntfy/cache/user.db`
- Auth: `auth-default-access: deny-all` — token-based auth required for all access
- `behind-proxy: true` — reads real client IPs from nginx `X-Forwarded-For`
- Subscribe via ntfy app on phone → server `https://ntfy.example.net`
- Topic: `security-alerts`

**KidsApp (Children's Educational Platform)**
- a separate project, not mine — Node.js/Express backend + static HTML/CSS/JS frontend
- Docker image: `kids-app:latest` (built locally from `~/docker/kids-app/Dockerfile`)
- Docker network: `docker_management` (bridge: `br-management`)
- Static IP: `172.18.0.90` on `docker_management` network
- Domain: `kids.example.net` (DuckDNS → `<WAN-IP>`)
- SSL cert: `~/docker/certbot/conf/live/kids.example.net/` (expires 2026-08-05, auto-renews with all other certs)
- Traffic flow: `Internet → nginx (172.18.0.100:443) → proxy_pass http://172.18.0.90:3000 → kids-app container`
- Database: SQLite at `/data/database.db` — backed by named volume `docker_kids-app-data` (survives rebuilds)
- Auto-saves to disk every 5 seconds via `setInterval(saveDB, 5000)`
- On startup, `db.js` runs `schema.sql` (safe — `CREATE TABLE IF NOT EXISTS`) then hardcoded migrations wrapped in try/catch
- Container runs as `node` user (UID 1000) — not root (May 7, 2026)
- `.env` file: `~/docker/kids-app/app/backend-node/.env` — created manually, never synced from git or baked into image
- AI calls: Groq (`api.groq.com`) blocked in Syria — proxied via Cloudflare Worker (`AI_PROXY_URL` in `.env`)
- Admin page: `https://kids.example.net/admin.html?key=<INTERNAL_ADMIN_API_KEY>` — 1-hour httpOnly cookie after first visit
- CSP headers: handled by Helmet in `app.js` (not nginx) — nginx sets `trust proxy 1` headers only
- Health check: `curl -sf http://172.18.0.90:3000/health` — returns `{"success":true}`
- CI/CD: GitHub Actions self-hosted runner (see below)
- File layout:
  ```
  ~/docker/kids-app/
  ├── Dockerfile
  └── app/
      ├── backend-node/
      │   ├── .env          ← secrets, never synced
      │   ├── server.js
      │   └── src/
      └── frontend/         ← static HTML/CSS/JS
  ```

**KidsApp CI/CD (GitHub Actions Self-Hosted Runner)**
- Runner binary: `~/actions-runner/` — runs as a systemd service
- Installed manually (GitHub CDN blocked in Syria)
- Trigger: push to `main` → `.github/workflows/deploy.yml`
- Deploy steps:
  1. Checkout repo on runner
  2. rsync code into `~/docker/kids-app/app/` (excludes `node_modules`, `.env`, `database.db`)
  3. Build image: `DOCKER_BUILDKIT=0 docker build --network docker_management -t kids-app:latest -f kids-app/Dockerfile kids-app/`
  4. Deploy: `docker compose up -d kids-app` (only kids-app container recreated)
  5. Health check: `curl -sf http://172.18.0.90:3000/health`
- `DOCKER_BUILDKIT=0` required — BuildKit has a silent `npm ci` bug on this server and doesn't support `--network`

**Simple Task Manager (TaskApp — Laravel Task App)**
- Personal task manager — Laravel 11 + Vite/Tailwind frontend, all-in-one image (php-fpm + internal nginx + supervisord)
- Source repo: `https://github.com/homelab/simple-task-manager` — `main` is the single source of truth
- Image: `ghcr.io/<user>/tasks:latest` (public GHCR, also tagged `:sha-<short>` per build)
- CI/CD: `.github/workflows/build-and-deploy.yml` builds the Dockerfile on every push to `main` with Buildx + gha cache, pushes to GHCR. Watchtower on x-server (polling every 60s, label-scoped to `com.centurylinklabs.watchtower.enable=true`) detects the new digest and rolls this container — no SSH from CI, SSH stays LAN+VPN only.
- Deploy dir on server: `~/docker/tasks/` — contains only `docker-compose.prod.yml` + `.env`. No source code on the server; the prebuilt image is pulled from GHCR.
- Compose file: repo's `docker-compose.prod.yml` (verbatim on server). Repo's `docker-compose.yml` is the local dev / build-from-source variant.
- Docker network: `docker_management` (bridge: `br-management`)
- Static IP: `172.18.0.91` on `docker_management` network
- Domain: `tasks.example.net` (DuckDNS → `<WAN-IP>`)
- SSL cert: `~/docker/certbot/conf/live/tasks.example.net/` (issued 2026-05-18, expires 2026-08-16, auto-renews with all other certs)
- Traffic flow: `Internet → nginx-ssl (172.18.0.100:443) → proxy_pass http://172.18.0.91:80 → internal nginx → php-fpm`
- Database: SQLite at `/var/www/html/database/database.sqlite` — named volume `stm_stm-db` (survives rolls)
- Storage: Laravel storage dir at named volume `stm_stm-storage`
- `.env`: `~/docker/tasks/.env` — `APP_ENV=production`, `APP_URL=https://tasks.example.net`, `APP_KEY` set, never committed (excluded from image via `.dockerignore`)
- First/manual deploy: `cd ~/docker/tasks && docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d`
- Rollback to a previous image: edit `image:` in `docker-compose.prod.yml` to `ghcr.io/<user>/tasks:sha-<short>` and `up -d`
- Healthcheck: internal `wget -q -O- http://127.0.0.1/up` every 30s (Laravel's `/up` route)
- Auth: web registration is disabled (`routes/auth.php`); accounts are created with `docker exec tasks php artisan tinker`. Login + password-reset endpoints are rate-limited (`throttle:10,1` and `throttle:6,1`).

**Portfolio (portfolio — static personal site)**

> ⚠️ **The live site left this server on 2026-08-08.** `example.com` is now hosted on
> Cloudflare Workers (Static Assets) — see "Portfolio on Cloudflare" below. Everything in
> this subsection still describes a *working* container, but it now serves only
> `site.example.net` and functions as the rollback path. The GHCR → Watchtower pipeline
> is untouched and still rolls it on every push to `main`.

- Static portfolio — single `index.html` + `img/`, served by `nginx:alpine`
- Source repo: `https://github.com/homelab/portfolio` (private) — `main` is the single source of truth
- Image: `ghcr.io/<user>/portfolio:latest` (public GHCR, also tagged `:sha-<short>` per build)
- CI/CD: `.github/workflows/build.yml` builds the Dockerfile on every push to `main` with Buildx + gha cache, pushes to GHCR. Watchtower on x-server (polling every 60s, label-scoped to `com.centurylinklabs.watchtower.enable=true`) detects the new digest and rolls this container — no SSH from CI, SSH stays LAN+VPN only.
- Deploy dir on server: `~/docker/portfolio/` — contains only `docker-compose.prod.yml`. No source on the server; the prebuilt image is pulled from GHCR.
- Docker network: `docker_management` (bridge: `br-management`)
- Static IP: `172.18.0.92` on `docker_management` network
- Domains: `site.example.net` only. ~~`example.com` + `www.example.com`~~ moved to Cloudflare 2026-08-08 — registration is still Namecheap (free student-pack, valid until 2027-05) but the **nameservers are now Cloudflare's**, and the A records that pointed at `<WAN-IP>` are gone.
- SSL cert: `~/docker/certbot/conf/live/example.com/` — issued 2026-05-23, **expires 2026-08-21, will NOT renew**. HTTP-01 webroot needs the domain resolving to this box and it no longer does. **Remove `-d example.com -d www.example.com` from the renewal cron** or the Sunday 03:00 run fails and pushes a false SSL-failure alert to ntfy. Letting the cert lapse is fine — no vhost depends on it once the stale server blocks are removed.
- Traffic flow: `Internet → nginx-ssl (172.18.0.100:443) → proxy_pass http://172.18.0.92:80 → nginx:alpine`
- First/manual deploy: `cd ~/docker/portfolio && docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d`
- Rollback to a previous image: edit `image:` in `docker-compose.prod.yml` to `ghcr.io/<user>/portfolio:sha-<short>` and `up -d`
- Healthcheck: `wget -q -O- http://127.0.0.1/` every 30s
- Note: `https://site.example.net/` reverse-proxies to this container and is now the only front door on x-server. It keeps pointing `rel=canonical` at `https://example.com/...`, which is still the right target — that URL is just served by Cloudflare now.

**Portfolio on Cloudflare (where the live site actually is, since 2026-08-08)**
- **Why:** solar power cuts every 1–4 days and x-server dies on each one. The portfolio is the
  one service with an outside audience, so it moved to hosting that survives the house losing
  power. Verified the same day — x-server was powered off and the site kept serving.
- **Platform:** Cloudflare **Workers with Static Assets**. Cloudflare put Pages into maintenance
  mode in April 2025, so the Git integration provisions a Worker, not a Pages project.
- **Why not GitHub Pages:** Pages needs the repo public *or* Student Pack Pro to stay active.
  Workers serves a private repo on the free tier with no bandwidth cap.
- **Build:** `bash scripts/build-static.sh` → `dist`. The build step exists so the repo root
  isn't the publish root — `docker-compose.prod.yml` carries this server's internal Docker IPs
  and shouldn't be publicly fetchable. `_headers` carries the security headers (verified live:
  HSTS, `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`).
- **Repo commits:** `444c5e2` (build script + `_headers`), `ac3c37e` (`wrangler.jsonc`,
  assets-only, no `main` entrypoint).
- **DNS:** Namecheap → Cloudflare nameservers; delegation flipped in ~10 minutes. All five MX
  records and the TXT carried over — that TXT is the Search Console verification.
- **Hostname wiring:** apex is a Worker **Custom Domain**. `www` refused a Custom Domain attach,
  so it's a proxied CNAME → apex plus a wildcard **Redirect Rule** (301, path + query preserved,
  same behaviour the nginx `www` block had). "Always Use HTTPS" is on.
- **Gotcha — Custom Domain vs. existing record:** the attach fails while any A/CNAME exists for
  that hostname. Delete the record first, which briefly takes the hostname dark — do the delete
  and the attach back to back.
- **Gotcha — stale resolvers:** cached answers reported `server: nginx` and `www` still on
  x-server well after cutover, twice. Verify with `curl --resolve <host>:443:<cloudflare-ip>`,
  never a bare `curl` from WSL.
- **Gotcha — new Redirect Rules 522 briefly:** a just-saved rule can 522 on individual PoPs for
  about a minute. Retry before debugging.
- **Dropped in the move:** Namecheap's free email forwarding only works on Namecheap
  nameservers, so it's gone. Nothing depended on it (the CV lists a Gmail address). Cloudflare
  Email Routing covers it if `@example.com` is ever needed.

**Watchtower (Image Auto-Roller)**
- `containrrr/watchtower:1.7.1`, container `watchtower`, deploy dir `~/docker/watchtower/`
- Label-scoped: rolls containers carrying `com.centurylinklabs.watchtower.enable=true` (`tasks`, `portfolio`)
- Poll interval: 60s. `WATCHTOWER_CLEANUP=true` removes old image layers after a successful roll.
- Pinned env `DOCKER_API_VERSION=1.44` — x-server's Docker daemon (29.x) requires API ≥1.44; Watchtower's bundled SDK negotiates 1.25 by default and gets rejected without the pin.
- Attached to `docker_management` network for working egress to ghcr.io (default bridge has no MASQUERADE due to `iptables: false`).
- Logs: `docker logs watchtower`. A "Session done … Updated=1" line confirms a roll.

**Nginx Watcher (Breach Detection)**
- Python daemon that tails `~/docker/nginx-logs/access.log` in real time
- Philosophy: alert on **outcomes, not attempts**. Scans/probes hit every public IP constantly, so alerting on them is noise. The watcher fires on exactly one thing: a request to a path that can never legitimately succeed on this stack (WordPress, phpMyAdmin, `.env`/`.git`, config dumps, LFI/traversal) that nonetheless returned **2xx** — i.e. a probe that actually *found* something
- Matches the path component only (strips query string) so junk params like `/?phpinfo=1` on the homepage don't false-positive
- Breach alert carries a one-tap **[Ban this IP]** action button (publishes to `server-cmd` via the publish-only `NTFY_CMD_TOKEN`)
- **SHADOW mode flag** (`SHADOW` in the script): when `True`, breaches are only logged (`WOULD ALERT …`) and not pushed — run this way ~24h against real traffic to confirm zero false positives, then set `False` to go live
- Scan counts / top attacker IPs / attack-attempt volume are **not pushed** — they're computed on-read by `daily-summary.sh` from the access log
- 10-minute cooldown per `(ip, path)`; authenticates via `NTFY_TOKEN` (from `EnvironmentFile`)
- `nginx-watcher.service` · `~/scripts/nginx-watcher.py` · state `~/.local/state/nginx-watcher/state.json`
- Ignores internal IPs: `127.0.0.1`, `172.18.0.1`, `192.168.1.10`, `<WAN-IP>`

**Login Watcher (Host Intrusion Alerting)**
- Python daemon that follows the journal (`journalctl -f -t sshd -t sudo`)
- Pushes (urgent) on two near-impossible events: a successful SSH login whose source is **outside** the LAN (`192.168.1.0/24`) + VPN (`10.0.0.0/24`), and a sudo session opened by a user other than `homelab`/`root`
- Chosen over a `pam_exec` hook deliberately: no SSH-lockout risk, and it's version-controlled/deployed by `deploy.sh` (a `/etc/pam.d` edit is neither)
- Runs as `homelab` (in the `adm` group → reads the journal without sudo)
- `login-watcher.service` · `~/scripts/login-watcher.py`

**Server Command Listener (Remote Management via ntfy)**
- Python daemon that subscribes to the `server-cmd` ntfy topic and executes commands
- Send commands from phone via ntfy app, results returned to `security-alerts` topic
- Commands: `ban <IP>`, `unban <IP>`, `status`, `attacks`, `restart <container|nginx|watcher>`, `hibernate`, `help`
- `restart` accepts container names (`nginx-ssl`, `ntfy`, `kids-app`, `tasks`, `portfolio`, `watchtower`) so server-health's one-tap **[Restart]** button works for any app
- Two ntfy tokens in `~/.config/ntfy-token.env`: `NTFY_TOKEN` (admin, used by the daemons) and `NTFY_CMD_TOKEN` (write-only to `server-cmd`, used only to back the action buttons — least privilege so a leaked notification can't read alerts)
- Runs as systemd service: `server-cmd.service`
- Script: `~/scripts/server-cmd.py`
- Requires sudoers rule (`/etc/sudoers.d/server-cmd`) for WireGuard status, hibernate, and watcher restart

**WireGuard VPN (Remote LAN Access)**
- Installed natively (kernel module, not Docker)
- Config: `/etc/wireguard/wg0.conf`
- Interface: `wg0`
- VPN subnet: `10.0.0.0/24`
- Server: `10.0.0.1`, port `51820/udp`
- Endpoint: `<WAN-IP>:51820`
- Masquerade: VPN clients appear as `192.168.1.10` to other LAN devices
- Forward rules in `/etc/ufw/before.rules` allow VPN → LAN traffic
- Starts on boot: `systemctl enable wg-quick@wg0`
- Clients:
  - Phone: `10.0.0.2` (split tunnel — only LAN/VPN traffic routed through tunnel)

### Docker Networks
```
docker_management  (br-management, 172.18.0.0/16)    — Nginx (172.18.0.100), ntfy (172.18.0.83), kids-app (172.18.0.90), tasks (172.18.0.91), portfolio (172.18.0.92)
```
- `br-management` is a stable bridge name set via `driver_opts` in docker-compose — survives network recreation
- Nginx has a static IP (`172.18.0.100`) pinned in docker-compose to match DNAT rules in `/etc/ufw/before.rules`

---

## 🌐 SERVICE ACCESS

### From LAN
```
Portfolio:        https://site.example.net  (this server. The real site — https://example.com — is on Cloudflare, not here)
ntfy:             http://192.168.1.10:8083 or https://ntfy.example.net
SSH:              ssh x-server
Samba:            \\192.168.1.10\files
```

### From the Internet
```
Portfolio:        https://example.com (canonical, www → 301 → apex) — served by CLOUDFLARE, not x-server
Portfolio (alt):  https://site.example.net (x-server container, rel=canonical → .me, rollback path)
ntfy:             https://ntfy.example.net (auth required)
KidsApp:      https://kids.example.net
Tasks (TaskApp):      https://tasks.example.net
```

### From VPN (WireGuard)
```
Everything on LAN (via masquerade) + full 192.168.1.0/24 network access
ntfy:        https://ntfy.example.net or http://192.168.1.10:8083
SSH:         ssh x-server (via 10.0.0.1 or 192.168.1.10)
Samba:       \\192.168.1.10\files
Router:      http://192.168.1.1 (or whatever router IP)
N-server:    http://192.168.1.11
```
All other services are LAN/VPN-only for security.

### Multi-Site Hosting
One IP hosts multiple websites using Nginx virtual hosts. Each domain gets its own server block, Let's Encrypt cert, and isolated directory.

**Active Sites:**
```
site.example.net      → reverse proxy → 172.18.0.92:80   (portfolio container; rel=canonical to .me, rollback path)
kids.example.net   → reverse proxy → 172.18.0.90:3000 (a family member's app)
tasks.example.net     → reverse proxy → 172.18.0.91:80   (TaskApp Laravel app)
```

**Stale (kept for rollback, no traffic):** the `example.com` and `www.example.com` server
blocks are still in `nginx.conf` but their DNS points at Cloudflare as of 2026-08-08. Remove
them — and their certbot `-d` entries — once the server role swap is settled.

**Adding new sites:** `bash ~/scripts/add-site.sh <domain>` — see [Multi-Site Script](#multi-site-script) below.

When ready for a paid domain ($15/yr), subdomains are unlimited:
```
example.com            → portfolio
guest.example.com      → a friend's site
blog.example.com       → blog
```

---

## 📁 IMPORTANT FILE LOCATIONS

### Configuration
```
SSH server config:      /etc/ssh/sshd_config
SSH client config:      ~/.ssh/config (on laptop)
SSH key (laptop):       ~/.ssh/x-server-new
Docker daemon config:   /etc/docker/daemon.json
UFW before.rules:       /etc/ufw/before.rules (Docker NAT/FORWARD + WireGuard FORWARD rules)
Docker Compose (main):  ~/docker/docker-compose.yml
Nginx config:           ~/docker/nginx.conf
Banned IPs config:      ~/docker/banned-ips.conf (included in all nginx server blocks)
Nginx logs:             ~/docker/nginx-logs/access.log (persistent, survives restarts)
Certbot certs:          ~/docker/certbot/conf/live/site.example.net/
Certbot certs (ntfy):   ~/docker/certbot/conf/live/ntfy.example.net/
Certbot certs (kids-app): ~/docker/certbot/conf/live/kids.example.net/
KidsApp Dockerfile:      ~/docker/kids-app/Dockerfile
KidsApp app code:        ~/docker/kids-app/app/
KidsApp backend:         ~/docker/kids-app/app/backend-node/
KidsApp frontend:        ~/docker/kids-app/app/frontend/
KidsApp .env:            ~/docker/kids-app/app/backend-node/.env (secrets, never synced)
KidsApp database volume: docker_kids-app-data → /data/database.db (inside container)
KidsApp CI/CD runner:    ~/actions-runner/
ntfy config:            ~/docker/ntfy/etc/server.yml
ntfy cache:             ~/docker/ntfy/cache/
ntfy auth DB:           ~/docker/ntfy/cache/user.db
Watcher script:         ~/scripts/nginx-watcher.py
Watcher state:          ~/.local/state/nginx-watcher/state.json
Watcher service:        /etc/systemd/system/nginx-watcher.service
Server cmd script:      ~/scripts/server-cmd.py
Server cmd service:     /etc/systemd/system/server-cmd.service
Sudoers (server-cmd):   /etc/sudoers.d/server-cmd
WoL service:            /etc/systemd/system/wol.service
Power watchdog service: /etc/systemd/system/power-watchdog.service
WireGuard config:       /etc/wireguard/wg0.conf (mode 600)
GRUB config:            /etc/default/grub (resume params for hibernate)
Swap file:              /swap.img (6GB)
Zsh config:             ~/.zshrc
Custom MOTD:            /etc/update-motd.d/01-custom
ntfy token env:         ~/.config/ntfy-token.env (mode 600, single source for all scripts/services)
AIDE custom config:     /etc/aide/aide.conf.d/99_x-server
AIDE database:          /var/lib/aide/aide.db
AIDE check script:      ~/scripts/aide-check.sh
rsyslog forwarding:     /etc/rsyslog.d/10-forward-to-nserver.conf (x-server → n-server)
UFW before.rules backup: /etc/ufw/before.rules.bak.20260414
```

### Scripts (`~/scripts/`)
```
Add site script:        ~/scripts/add-site.sh
Log viewer:             ~/scripts/nginx-logwatch.sh (10 modes: summary, attacks, visitors, live, etc.)
IP ban manager:         ~/scripts/ban-ip.sh (ban, unban, list, check, auto-ban)
Nginx watcher:          ~/scripts/nginx-watcher.py (breach detection — exploit path returns 2xx — runs as systemd service)
Login watcher:          ~/scripts/login-watcher.py (external SSH / unexpected sudo via journald — runs as systemd service)
Server command listener: ~/scripts/server-cmd.py (remote management via ntfy — runs as systemd service)
ntfy sender:            ~/scripts/ntfy-send.sh (helper — sends authenticated ntfy notifications, used by all monitoring scripts)
Server health check:    ~/scripts/server-health.sh (disk space + container monitoring — runs every 10 min via cron)
Daily summary:          ~/scripts/daily-summary.sh (morning briefing notification — runs daily at 8 AM via cron)
Backup script:          ~/scripts/backup.sh (active — runs weekly via root crontab, notifies on failure only; age shown in daily summary)
Power watchdog:         ~/scripts/power-watchdog.sh (hibernate on low battery + rtcwake cycle — runs as systemd service)
AIDE integrity check:   ~/scripts/aide-check.sh (daily cron, notifies via ntfy on changes)
Backup destination:     /mnt/storage/backup/
```

### Laptop (WSL)
```
Pull backup script:     ~/scripts/code-scripts/pull-backup.sh
Local backups:          ~/x-server-backups/
Quartz notes archive:   ~/notes-archive/           (markdown source, retired 2026-05-23)
Quartz HTML snapshot:   ~/quartz-notes.tar.gz      (final built site, retired 2026-05-23)
```

### Data Storage
```
Personal files:         /mnt/storage/files/
Main storage mount:     /mnt/storage/
Backups:                /mnt/storage/backup/
Samba config:           /etc/samba/smb.conf
```

---

## ⚡ ESSENTIAL COMMANDS

### Docker
```bash
cd ~/docker
docker compose up -d              # Start all services
docker compose down               # Stop all services
docker compose restart             # Restart all
docker compose ps                  # Check status
docker compose logs -f <service>   # Live logs
docker compose pull                # Update images
docker system prune -a             # Clean unused images
```

### WireGuard VPN
```bash
sudo wg show                          # Status + connected peers
sudo wg-quick up wg0                  # Start VPN
sudo wg-quick down wg0                # Stop VPN
sudo systemctl status wg-quick@wg0    # Service status
sudo nano /etc/wireguard/wg0.conf     # Edit config (stop first)
```

**Adding a new client:**
```bash
# Generate key pair
wg genkey | tee /dev/stderr | wg pubkey

# Add [Peer] block to /etc/wireguard/wg0.conf (stop wg0 first):
# [Peer]
# PublicKey = <client-public-key>
# AllowedIPs = 10.0.0.X/32

# Generate QR for phone:
qrencode -t ansiutf8 << 'EOF'
[Interface]
PrivateKey = <client-private-key>
Address = 10.0.0.X/24
DNS = 1.1.1.1

[Peer]
PublicKey = cKwXfV2es870iRiHFvD4EEXOQelJmezvEJRguOzkjjQ=
Endpoint = <WAN-IP>:51820
AllowedIPs = 192.168.1.0/24, 10.0.0.0/24
EOF
```

**Revoking a client:** Remove its `[Peer]` block from `wg0.conf`, then restart wg0.

### SSL Certificate
```bash
# Manual renewal (auto-renewal runs Sundays at 3 AM)
docker run --rm \
  --network docker_management \
  -v ~/docker/certbot/conf:/etc/letsencrypt \
  -v ~/docker/certbot/www:/var/www/certbot \
  certbot/certbot renew
docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload
```

### Nginx Log Monitoring
```bash
bash ~/scripts/nginx-logwatch.sh              # Quick daily dashboard
bash ~/scripts/nginx-logwatch.sh attacks       # Blocked attacks (403/444)
bash ~/scripts/nginx-logwatch.sh suspects      # Suspicious 200 responses
bash ~/scripts/nginx-logwatch.sh visitors      # Real human visitors (bots filtered)
bash ~/scripts/nginx-logwatch.sh top-ips       # Top IPs with blocked count
bash ~/scripts/nginx-logwatch.sh top-paths     # Most requested paths
bash ~/scripts/nginx-logwatch.sh status        # Color-coded status breakdown
bash ~/scripts/nginx-logwatch.sh live          # Real-time color-coded tail
bash ~/scripts/nginx-logwatch.sh hourly        # Requests per hour with bar chart
bash ~/scripts/nginx-logwatch.sh ip 1.2.3.4    # All requests from a specific IP
bash ~/scripts/nginx-logwatch.sh full -n 100   # Raw last 100 lines
```

### IP Ban Management
```bash
bash ~/scripts/ban-ip.sh ban 1.2.3.4 "reason"   # Ban IP with reason
bash ~/scripts/ban-ip.sh ban 1.2.3.0/24          # Ban subnet
bash ~/scripts/ban-ip.sh unban 1.2.3.4            # Remove ban
bash ~/scripts/ban-ip.sh list                      # Show all bans
bash ~/scripts/ban-ip.sh check 1.2.3.4            # Check if banned
bash ~/scripts/ban-ip.sh auto-ban                  # Auto-ban from logs (runs hourly via cron)
```

### System Monitoring
```bash
htop              # System resources
df -h             # Disk usage
free -h           # RAM usage
docker stats      # Container resources
```

### Remote Management (via ntfy phone app)
Send any of these commands to the `server-cmd` topic on ntfy:
```
help                          # List all commands
ban <IP> [reason]             # Ban an IP and reload nginx
unban <IP>                    # Remove ban and reload nginx
status                        # Uptime, load, memory, disk, containers, WireGuard peers
attacks                       # Top 10 blocked IPs from recent logs
restart <nginx|ntfy|watcher>  # Restart a service
hibernate                     # Hibernate server (5-second delay)
```
Results are sent back to the `security-alerts` topic.

### Security Checks
```bash
sudo ufw status numbered                  # Firewall rules
sudo fail2ban-client status sshd          # SSH ban status
sudo ss -tlnp | grep -v '192.168.1.10'  # Check for services on wrong interfaces
sudo iptables -L DOCKER -n               # Verify Docker not bypassing UFW (should show "No chain" with iptables:false)
sudo iptables -L ufw-before-forward -n   # Verify Docker bridge forward rules loaded
sudo iptables -t nat -L POSTROUTING -n   # Verify MASQUERADE rule for Docker subnet
sudo iptables -t nat -L PREROUTING -n    # Verify DNAT rules for nginx (172.18.0.100:80/:443)
ip link show br-management               # Verify stable bridge name exists
docker network inspect docker_management --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'  # Verify container IPs (nginx .100, ntfy .83, kids-app .90)
docker compose exec -T kids-app whoami                 # Verify kids-app runs as 'node' (not root)
curl -sf http://172.18.0.90:3000/health              # Verify kids-app health
sudo aide --check --config /etc/aide/aide.conf   # File integrity check (should report NO differences)
sudo grep "x-server" /var/log/syslog | tail -5    # Verify syslog forwarding (run on n-server)
grep 'tk_' ~/scripts/*.py ~/scripts/*.sh          # Verify no hardcoded tokens in scripts (should return nothing)
sudo apt update && sudo apt upgrade       # System updates
```

### Multi-Site Management
```bash
bash ~/scripts/add-site.sh <domain>       # Add a new friend's site (full workflow)
ls ~/docker/website-*/                    # List all friend site directories
grep "server_name" ~/docker/nginx.conf    # See all configured domains
sudo ls ~/docker/certbot/conf/live/       # List all SSL certificates
```

### Cron Jobs

**User crontab (`crontab -l`):**
```
# SSL renewal — every Sunday at 3 AM (notifies on success/failure)
0 3 * * 0 docker run --rm --network docker_management -v /home/homelab/docker/certbot/conf:/etc/letsencrypt -v /home/homelab/docker/certbot/www:/var/www/certbot certbot/certbot renew --quiet && docker compose -f /home/homelab/docker/docker-compose.yml exec -T nginx nginx -s reload && bash /home/homelab/scripts/ntfy-send.sh "SSL Renewed" "All certs renewed successfully" "default" "lock" || bash /home/homelab/scripts/ntfy-send.sh "SSL Renewal Failed" "certbot renew or nginx reload failed — check manually" "urgent" "warning,lock"

# Rotate nginx logs — every Sunday at 4 AM, keep 4 weeks
0 4 * * 0 cd ~/docker/nginx-logs && mv -f access.log.3 access.log.4 2>/dev/null; mv -f access.log.2 access.log.3 2>/dev/null; mv -f access.log.1 access.log.2 2>/dev/null; mv -f access.log access.log.1 2>/dev/null; docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reopen

# Auto-ban repeat offenders — every hour at XX:05 (not XX:00, router restarts daily at 5:00 AM)
5 * * * * bash /home/homelab/scripts/ban-ip.sh auto-ban

# Health check — every 10 minutes (disk space, container health)
*/10 * * * * bash /home/homelab/scripts/server-health.sh

# Daily summary — every day at 8 AM (system stats, nginx stats, VPN status)
0 8 * * * bash /home/homelab/scripts/daily-summary.sh
```

**Root crontab (`sudo crontab -l`):**
```
# Weekly backup — every Tuesday at 2 AM (notifies on success/failure)
0 2 * * 2 bash /home/homelab/scripts/backup.sh && bash /home/homelab/scripts/ntfy-send.sh "Backup Complete" "Weekly backup finished successfully" "default" "floppy_disk" || bash /home/homelab/scripts/ntfy-send.sh "Backup Failed" "Weekly backup script failed — check logs" "urgent" "warning,floppy_disk"

# AIDE integrity check — daily at 3:30 AM (notifies via ntfy on file changes)
30 3 * * * bash /home/homelab/scripts/aide-check.sh
```

⚠️ Backup runs as root because it reads system configs (`/etc/ssh/sshd_config`, `/etc/docker/daemon.json`, `/etc/ufw/before.rules`). All other cron jobs run as homelab.

### Custom Systemd Services

| Service | Command | Purpose |
|---------|---------|---------|
| `nginx-watcher.service` | `python3 ~/scripts/nginx-watcher.py` | Real-time nginx log monitoring with security alerts via ntfy |
| `server-cmd.service` | `python3 ~/scripts/server-cmd.py` | Remote server management via ntfy (ban/unban, status, restart, hibernate) |
| `boot-notify.service` | `bash ~/scripts/ntfy-send.sh` | Sends ntfy notification on server boot (oneshot) |
| `wol.service` | `/sbin/ethtool -s enp3s0 wol g` | Re-enables Wake-on-LAN on every boot (oneshot) |
| `power-watchdog.service` | `bash ~/scripts/power-watchdog.sh` | Monitors AC/battery, hibernates on low battery with rtcwake wake cycle |

```bash
sudo systemctl status nginx-watcher    # Check status
journalctl -u nginx-watcher -f         # View logs
sudo systemctl restart nginx-watcher   # Restart

sudo systemctl status server-cmd       # Check status
journalctl -u server-cmd -f            # View logs
sudo systemctl restart server-cmd      # Restart

sudo systemctl status boot-notify      # Check last boot notification
sudo systemctl start boot-notify       # Test (sends notification now)

sudo systemctl status power-watchdog   # Check power watchdog
journalctl -u power-watchdog -f        # View power watchdog logs
```

---

## 🌐 MULTI-SITE SCRIPT (`add-site.sh`)

**File:** `~/scripts/add-site.sh`

Automates adding a new website for a friend. One command handles directory creation, Docker volume, Nginx config, SSL certificate, and reload.

### Usage

```bash
bash ~/scripts/add-site.sh <domain>
# Example:
bash ~/scripts/add-site.sh app.example.net
```

### Before Running

1. Register the subdomain on https://app.example.net
2. Point it to your IP (`<WAN-IP>`)

### What It Does

1. Creates `~/docker/website-<name>/` with a placeholder `index.html`
2. Adds a volume mount to `docker-compose.yml` → `/usr/share/nginx/sites/<name>:ro`
3. Adds an HTTP server block to `nginx.conf` (ACME challenge + HTTPS redirect)
4. Recreates Nginx container to pick up the new volume
5. Gets a Let's Encrypt SSL certificate via certbot (runs on `docker_management` network)
6. Adds an HTTPS server block to `nginx.conf` (full security headers, rate limiting, map-based bot/query/URI filtering, banned IPs, method restriction, static asset caching)
7. Reloads Nginx (via `exec nginx -s reload`, zero downtime)

### Security Per Site

Each friend's site gets the same security as the main site:
- TLS 1.2/1.3, strong ciphers, HSTS
- All security headers (X-Frame-Options, X-Content-Type-Options, etc.)
- Stricter CSP than main site (no `unsafe-eval`, no external CDNs)
- Rate limiting (10 req/s, burst 20)
- Map-based bot/query string/URI filtering (`$bad_ua`, `$bad_qs`, `$bad_uri`)
- IP banning via `banned-ips.conf` (shared across all sites)
- Method restriction (GET/HEAD only)
- Static asset caching (7 days)

### Important Notes

- The script is **idempotent** — safe to re-run; it skips completed steps
- Friend site volumes mount to `/usr/share/nginx/sites/<name>` (not inside `/html` which is read-only)
- Certbot runs on `docker_management` network (default `docker0` bridge has no outbound due to `iptables: false`)
- Certificate check uses `sudo test -d` (certbot dirs are root-owned)
- `certbot renew` handles all certificates — no per-site cron needed
- Let's Encrypt email: `<account-email>`

### Hosted Sites

| Domain | Directory | Added |
|--------|-----------|-------|
| `site.example.net` | `~/docker/website/` | Original |
| `ntfy.example.net` | Reverse proxy → `172.18.0.83:80` (ntfy container) | April 13, 2026 |
| `kids.example.net` | Reverse proxy → `172.18.0.90:3000` (kids-app container) | May 7, 2026 |

---

## 📊 RESOURCE USAGE

```
Nginx:                 ~8MB
ntfy:                  ~48MB
kids-app:                ~109MB (Node.js)
nginx-watcher:         ~16MB (Python, runs on host)
server-cmd:            ~16MB (Python, runs on host)
──────────────────────────────
Containers total:      ~165MB
Base Ubuntu:           ~400MB
Host services:         ~32MB
──────────────────────────────
Total:                 ~597MB / 5.6GiB
Available:             ~4.7GiB
```

**Disk:**
```
SSD (/):           13GB used / 98GB (14%) — ~120GB unallocated in LVM
HDD (/mnt/storage): ~134GB used / 293GB (49%)
```

---

## 🚨 KNOWN ISSUES & SOLUTIONS

### 1. Docker Bypasses UFW
- **Issue:** Docker manipulates iptables directly, ignoring UFW rules
- **Solution:** Set `"iptables": false` in `/etc/docker/daemon.json`
- **Side effect:** Containers lose outbound internet — requires manual NAT/FORWARD rules in `/etc/ufw/before.rules`
- **Status:** ✅ Fixed (both bypass and outbound access restored)

### 2. Docker Containers No Outbound Access (iptables: false)
- **Issue:** With `"iptables": false`, Docker cannot create NAT rules. Containers can't reach the internet.
- **Root cause:** No MASQUERADE rule for container subnet, and UFW FORWARD policy is DROP
- **Solution:** Add NAT and FORWARD rules to `/etc/ufw/before.rules` referencing the Docker bridge interface (`br-management`)
- **Bridge name stability:** Bridge is now named `br-management` via `driver_opts` in docker-compose.yml — survives network recreation
- **Status:** ✅ Fixed (March 7, 2026; bridge name stabilized March 13, 2026)

### 3. GitHub CDN Blocked (Syria)
- **Issue:** Can't download from GitHub CDN directly on server
- **Solution:** Download on laptop → SCP to server
- **Impact:** Slow Docker pulls (9–14 KB/s)

### 4. WiFi Exclamation Mark with Pi-hole
- **Cause:** Pi-hole blocking connectivity check domains
- **Solution:** Whitelist: `connectivitycheck.gstatic.com`, `captive.apple.com`, `msftconnecttest.com`
- **Status:** 🗑️ N/A — Pi-hole moved to N-server (April 12, 2026)

### 5. Nginx Config Shell Escaping
- **Issue:** Writing nginx.conf via heredoc (`<< 'EOF'`) can escape `$` and `;` characters
- **Solution:** Always use a unique delimiter like `NGINXEOF` and verify with `cat -n` before restarting
- **Check:** `docker compose logs nginx --tail 5` after any config change

### 6. systemd-resolved Port Conflict
- **Issue:** Blocked port 53 (needed for Pi-hole)
- **Solution:** Disabled systemd-resolved, Pi-hole handles DNS
- **Status:** 🗑️ Pi-hole moved to N-server (April 12, 2026) — systemd-resolved still disabled

### 7. Telegram Bot Crash-Looping (Syria)
- **Issue:** Container restarting every ~60s for 2 weeks
- **Root cause:** `api.telegram.org` is blocked in Syria — bot can't connect
- **Fix applied:** Container stopped, source code deleted
- **Status:** 🗑️ Removed (March 8, 2026)

### 8. ttyd Web Terminal Crash-Looping
- **Issue:** Container exiting with code 127, restarting continuously
- **Root cause:** Missing binary or misconfiguration
- **Status:** 🗑️ Removed (March 8, 2026)

### 9. Pi-hole Blocklists Partially Blocked (Syria)
- **Issue:** Some blocklist sources fail to download (Connection Refused)
- **Previously blocked:** `raw.githubusercontent.com`, `adaway.org`, `adguardteam.github.io` — now mostly resolved
- **Current:** 10 of 10 lists active, 671k+ domains blocked
- **Working lists:** Phishing Army, URLhaus, Peter Lowe's, Firebog (Easylist, Easyprivacy, Admiral, Prigent-Ads, Prigent-Crypto), someonewhocares, OISD (big)
- **Status:** 🗑️ Pi-hole moved to N-server (April 12, 2026)

### 10. Certbot Needs `--network docker_management`
- **Issue:** `docker run --rm` certbot containers can't resolve DNS — certificate requests fail with `NameResolutionError`
- **Root cause:** `docker run --rm` uses the default `docker0` bridge, which has no outbound NAT rules (only `docker_management` has NAT/FORWARD in `before.rules`)
- **Solution:** Always use `--network docker_management` when running certbot: `docker run --rm --network docker_management ...`
- **Also affects:** SSL cert auto-renewal cron — must include the network flag
- **Status:** ✅ Fixed (March 8, 2026)

### 11. CSP Blocking Boxicons and Google Fonts
- **Issue:** Icons and custom fonts not loading — CSP `style-src` and `font-src` only allowed `'self'`
- **Root cause:** Boxicons (cdn.jsdelivr.net) and Google Fonts (fonts.googleapis.com / fonts.gstatic.com) are external CDNs
- **Solution:** Whitelist both domains in CSP — `style-src` for CSS, `font-src` for .woff2 files
- **Also:** Boxicons was loaded with `preload` + `onload="..."` inline JS — CSP blocked the inline handler. Replaced with plain `<link rel="stylesheet">`
- **Status:** ✅ Fixed (March 14, 2026)

### 12. CSP Blocking Inline Script
- **Issue:** Main site's inline `<script>` block (mobile nav, theme toggle) blocked by CSP `script-src`
- **Root cause:** Inline scripts require either `'unsafe-inline'` (insecure) or a SHA-256 hash
- **Solution:** Added the browser-provided SHA-256 hash to `script-src`: `'sha256-4Yl3oGJUyYFPI2ANm/uDNVUNRymDxZtv/gJOI3UNCLc='`
- **⚠️ Note:** If the inline script content changes, the hash changes — browser console will show the new hash
- **Status:** ✅ Fixed (March 14, 2026)

### 13. `docker compose restart` Doesn't Pick Up New Volumes
- **Issue:** After adding `banned-ips.conf` volume to docker-compose.yml, `restart` caused nginx to crash-loop — file not found inside container
- **Root cause:** `restart` only stops/starts the existing container. It does NOT recreate it with updated compose config
- **Solution:** Use `docker compose up -d nginx` to recreate the container with new volumes
- **Status:** ✅ Fixed (March 14, 2026)

### 14. Pi-hole Shows Docker Gateway IP (`172.18.0.1`) Instead of Real Device IPs
- **Issue:** All DNS queries in Pi-hole query log showed `172.18.0.1` (Docker bridge gateway) instead of the actual device IP (e.g. `192.168.1.106`)
- **Root cause:** Docker's userland proxy does SNAT on port-published traffic — same issue that affected nginx
- **Solution:** Same DNAT approach as nginx — pin Pi-hole to static IP `172.18.0.53`, remove Docker port 53 publishing, add DNAT+FORWARD rules in `/etc/ufw/before.rules` for UDP and TCP port 53
- **Additional fix required:** Pi-hole v6's dnsmasq defaults to `LOCAL` listening mode, which silently drops queries from different subnets (192.168.1.x → 172.18.0.x). Must set `pihole-FTL --config dns.listeningMode all`. The old env var `DNSMASQ_LISTENING` is silently ignored in v6.
- **Status:** 🗑️ Pi-hole moved to N-server (April 12, 2026)

### 15. Wake-on-LAN Not Functional from Shutdown (HP G62)
- **Issue:** WoL magic packet does not wake the server from powered-off state
- **Root cause:** HP G62 NIC loses standby power completely after shutdown — ethernet LED goes off, NIC can't listen for magic packets
- **WoL support:** Confirmed supported by NIC (`Supports Wake-on: pumbg`) and enabled (`wol g`), but hardware doesn't provide standby power
- **BIOS:** No "Wake on AC" or "Restore on AC Power Loss" option available
- **ACPI wake on charger:** Tested `systemctl suspend` + plug charger — does not wake
- **Workaround:** Hibernate + `rtcwake` periodic wake cycle (see Power Management section)
- **Status:** ⚠️ Hardware limitation — workaround in place

### 16. Groq API Blocked in Syria (KidsApp AI)
- **Issue:** `api.groq.com` not reachable from Syria — kids-app AI features fail
- **Solution:** AI calls proxied through a Cloudflare Worker (`AI_PROXY_URL` in kids-app `.env`)
- **Status:** ✅ Fixed (May 7, 2026)

---

## 💾 BACKUP & RESTORE

### Status: ✅ Working (April 30, 2026)

**Script:** `~/scripts/backup.sh`
**Destination:** `/mnt/storage/backup/`
**Schedule:** Every Tuesday at 2:00 AM (root crontab)
**Retention:** Last 4 backups (~1 month of Tuesdays)
**Size:** ~2.5MB compressed per backup
**Log:** `/mnt/storage/backup/backup.log`

### What Gets Backed Up
- `~/docker/docker-compose.yml`, `nginx.conf`, `banned-ips.conf`
- `/etc/docker/daemon.json`, `/etc/ssh/sshd_config`, `/etc/ufw/before.rules`
- `/etc/wireguard/wg0.conf`
- `/etc/samba/smb.conf`
- `/etc/aide/aide.conf.d/99_x-server` (AIDE custom rules)
- `/etc/rsyslog.d/10-forward-to-nserver.conf` (syslog forwarding config)
- `/etc/systemd/system/` — `wol.service`, `power-watchdog.service`, `nginx-watcher.service`, `server-cmd.service`
- `/etc/sudoers.d/server-cmd`
- Root crontab (saved as `root-crontab.txt`)
- `~/scripts/` (all server scripts)
- `~/.ssh/` and `~/.zshrc`
- `~/docker/website/` and `~/docker/website-*/` (all sites)
- `~/docker/certbot/conf/` (SSL certs)
- `~/docker/nginx-logs/` (access logs)
- `~/docker/ntfy/etc/` (ntfy server config)
- `~/docker/kids-app/Dockerfile` (build config)

### What Is NOT Backed Up
- `/mnt/storage/files/` (140GB) — too large for local backup. If the HDD fails, uploaded files are gone.
- `kids-app-data` Docker volume (`/data/database.db`) — ⚠️ not yet included in backup. Code is in GitHub, `.env` is manual-only on server. Database should be added to `backup.sh`.
- `~/docker/kids-app/app/backend-node/.env` — ⚠️ secrets file, created manually on server, not in git. Should be added to `backup.sh`.

### How It Works
1. Runs as root (reads system configs without sudo issues)
2. Stages all files to `/tmp/backup-staging-$$`
3. Compresses everything into a dated `.tar.gz`
4. Verifies archive integrity with `tar -tzf` — fatal exit if corrupt
5. Sets ownership to `homelab`
6. Rotates old backups (keeps last 4)

### DB Password
- No longer needed — MariaDB removed with Nextcloud (March 29, 2026)
- `/root/.backup-secrets` deleted (April 14, 2026)

### Manual Run
```bash
sudo bash ~/scripts/backup.sh
```

### Restore
```bash
# Extract a backup
mkdir /tmp/restore && cd /tmp/restore
tar -xzf /mnt/storage/backup/x-server-backup_YYYY-MM-DD_HH-MM.tar.gz

# Configs are in their respective directories:
# docker-configs/   → ~/docker/
# system-configs/   → /etc/docker/, /etc/ssh/, /etc/ufw/, /etc/wireguard/, /etc/samba/, /etc/aide/, /etc/rsyslog.d/
# systemd/          → /etc/systemd/system/
# sudoers/          → /etc/sudoers.d/
# root-crontab.txt  → sudo crontab -e (paste contents)
# scripts/          → ~/scripts/
# dot-ssh/          → ~/.ssh/
# website/          → ~/docker/website/
# certbot-conf/     → ~/docker/certbot/conf/
# nginx-logs/       → ~/docker/nginx-logs/
# ntfy-config/      → ~/docker/ntfy/etc/
```

### Off-Server Backup (Laptop)
Manual pull from WSL laptop:
```bash
bash ~/scripts/code-scripts/pull-backup.sh
```
- Uses SSH ControlMaster (single passphrase prompt)
- Downloads only the latest backup
- Skips if already downloaded
- Stores in `~/x-server-backups/`

---

## 🎨 SHELL CUSTOMIZATION

- Default shell: Zsh
- Framework: Oh My Zsh
- Theme: agnoster
- Custom MOTD on login with neofetch

---

## 🌍 SYRIA-SPECIFIC NOTES

1. GitHub CDN blocked → download on laptop first, SCP to server
2. Slow international routes → 9–14 KB/s Docker pulls
3. Some domains blocked → use alternative DNS
4. Online payments difficult → use free services (DuckDNS, Let's Encrypt)
5. CGNAT was common → now resolved with static IP from ISP
6. `api.telegram.org` blocked → Telegram bot removed
7. Several Pi-hole blocklist sources were previously blocked — mostly resolved as of March 2026 (Pi-hole now on N-server)
8. DNSSEC validation may fail on some queries due to ISP DNS interception
9. Frequent power outages (solar + grid) — server uses hibernate + rtcwake wake cycle for automatic recovery without manual intervention
10. `api.groq.com` blocked → kids-app AI calls proxied via Cloudflare Worker (`AI_PROXY_URL` in `.env`)

---

## 💰 COST

| Item             | Cost               |
| ---------------- | ------------------ |
| Hardware         | $0 (reused laptop) |
| Electricity      | ~$3–5/month        |
| Domain           | $0 (DuckDNS)       |
| SSL Certificate  | $0 (Let's Encrypt) |
| Static IP        | 5$                 |
| **Annual total** | **~$10**           |

---

## ⏳ PENDING TASKS

### Priority 1 — Monitoring
- ~~Prometheus + Grafana for server metrics~~ — basic monitoring now handled via ntfy (health checks, daily summary, boot alerts)
- Prometheus + Grafana still optional for graphing/dashboards if needed
- Syncthing on X-server (always-on relay between laptop and phone)

### Priority 2 — KidsApp Backup
- Add kids-app SQLite database (`docker_kids-app-data` volume) to `backup.sh`
- Add `~/docker/kids-app/app/backend-node/.env` to `backup.sh` — secrets file, manual-only, not in git

### Priority 3 — Cloudflare migration cleanup (after 2026-08-08)
- Remove `-d example.com -d www.example.com` from the certbot renewal cron **before 2026-08-21**, or the Sunday run fails and pushes a false SSL alert
- **Two monitoring scripts still name `example.com` and must be updated in the same change** — both pin to the local nginx IP rather than public DNS, so neither broke at cutover, but both go wrong once the cert lapses or the vhost is deleted:
  - `scripts/x-server/daily-summary.sh:14` — `DOMAINS=(...)` reads cert expiry via `openssl s_client -connect 172.18.0.100:443 -servername <d>`. After 2026-08-21 this reports an expired cert every morning with a ⚠. Drop `example.com` from the array.
  - `scripts/x-server/server-health.sh:134` — `check_http "example.com"` probes nginx every 10 min with `--resolve ...:443:172.18.0.100`. It still passes today because the vhost is still there; **delete the vhost without touching this line and the check starts hitting whatever nginx falls back to**, which makes it meaningless rather than loud. Drop the line when the vhost goes.
- Remove the stale `example.com` + `www.example.com` server blocks from `nginx.conf` — no DNS points at them (do this *after* the two script edits above)
- Decide the fate of the `portfolio` container + GHCR/Watchtower pipeline (currently a deliberate rollback path — keep until the server role swap is settled)

### Optional Enhancements
- ~~Cloudflare free tier (DDoS protection, CDN)~~ — now in use for `example.com` (Workers Static Assets, 2026-08-08)
- ~~Paid domain ($15/yr) with unlimited subdomains~~ — `example.com` registered free via Student Pack (Namecheap, valid to 2027-05)
- Paperless-ngx (document management)
- FreshRSS (RSS reader)
- Jellyfin (media server)

---

## ✅ COMPLETED

- ✅ Ubuntu Server 22.04 installed
- ✅ Dual-drive setup (SSD + HDD)
- ✅ Static public IP (<WAN-IP>)
- ✅ Domain: site.example.net
- ✅ HTTPS with Let's Encrypt (auto-renewal cron)
- ✅ Portfolio website deployed and live
- ✅ SSH hardening (new Ed25519 key, custom port, LAN-bound, Fail2ban)
- ✅ Firewall hardened for public internet (only 80/443 public)
- ✅ Docker iptables bypass fixed
- ✅ Nginx security hardened (Grade A on securityheaders.com)
- ✅ Rate limiting enabled
- ✅ Samba — LAN only (home + files shares)
- ✅ Cockpit disabled
- ✅ Nginx web server (public)
- ✅ Pi-hole (ad blocking) — moved to N-server (April 12, 2026)
- ✅ Homer (dashboard) — removed (April 12, 2026)
- ✅ WireGuard VPN — remote LAN access (April 12, 2026)
- ✅ Automatic security updates
- ✅ Custom shell (Zsh + Oh My Zsh)
- ✅ Port forwarding configured on router
- ✅ All services bound to LAN IP
- ✅ Nginx MIME types fixed (CSS loading)
- 🗑️ Digital garden (Quartz at /notes) — retired 2026-05-23, source archived to WSL `~/notes-archive/`
- ✅ Pi-hole DNS fixed — container outbound restored via UFW before.rules (March 7, 2026) — Pi-hole moved to N-server (April 12, 2026)
- ✅ Pi-hole setup script run — 671k domains blocked, 66 domains whitelisted, 27 blacklisted (March 15, 2026) — Pi-hole moved to N-server (April 12, 2026)
- ✅ Telegram bot stopped and restart disabled (March 7, 2026)
- ✅ Nextcloud config backup permissions fixed (March 7, 2026)
- ✅ Orphaned `~/server/` directory deleted (March 7, 2026)
- ✅ Orphaned `~/docker-compose-nextcloud.yml` deleted (March 7, 2026)
- ✅ Multi-site hosting with add-site.sh script (March 8, 2026)
- ✅ First friend site live: app.example.net (March 8, 2026)
- ✅ Server scripts organized into ~/scripts/ (March 8, 2026)
- ✅ Deploy script (`tool deploy`) added to WSL toolkit (March 8, 2026)
- ✅ SSL auto-renewal cron added with `--network docker_management` (March 8, 2026)
- ✅ Old `~/pihole/` directory removed — Pi-hole runs from main compose (March 8, 2026)
- ✅ Telegram bot removed — `api.telegram.org` blocked in Syria (March 8, 2026)
- ✅ Syncthing removed — never used (March 8, 2026)
- ✅ ttyd removed — was crash-looping (March 8, 2026)
- ✅ Self-signed LAN certs removed — unused (March 8, 2026)
- ✅ Orphaned `telegram-bot_default` Docker network removed (March 8, 2026)
- ✅ Nginx hardened — map-based UA/query string/URI filtering, method restriction, default catch-all server (March 13, 2026)
- ✅ Real client IP logging — DNAT rules bypass Docker proxy, nginx sees actual IPs (March 13, 2026)
- ✅ Docker bridge name stabilized — `br-management` via driver_opts, survives recreation (March 13, 2026)
- ✅ Nginx static IP pinned — `172.18.0.100` on management network (March 13, 2026)
- ✅ Nginx Docker port publishing removed — DNAT in before.rules handles routing (March 13, 2026)
- ✅ Attack log analysis — identified <WAN-IP> as own public IP, not attacker (March 13, 2026)
- ✅ Retired app.example.net — friend site, files + cert + nginx blocks removed (May 23, 2026)
- ✅ IP banning system — `banned-ips.conf` included in all server blocks, managed by `ban-ip.sh` (March 14, 2026)
- ✅ Auto-ban cron — hourly auto-ban of repeat offenders via `ban-ip.sh auto-ban` (March 14, 2026)
- ✅ Persistent nginx logs — `~/docker/nginx-logs/` mounted volume, survives container restarts (March 14, 2026)
- ✅ Log rotation cron — weekly, keeps 4 weeks of access logs (March 14, 2026)
- ✅ Log viewer script — `nginx-logwatch.sh` with 10 modes: summary, attacks, visitors, live, top-ips, etc. (March 14, 2026)
- ✅ CSP updated — whitelisted `cdn.jsdelivr.net` (Boxicons), `fonts.googleapis.com`/`fonts.gstatic.com` (Google Fonts), SHA-256 hash for inline script (March 14, 2026)
- ✅ SSL renewal cron fixed — uses `exec -T nginx nginx -s reload` instead of `docker compose restart` (March 14, 2026)
- ✅ add-site.sh updated — new sites get `banned-ips.conf` include, map-based filtering, `exec` reload (March 14, 2026)
- ✅ Hibernate power management — auto-hibernate on low battery + rtcwake wake cycle for hands-free recovery (April 13, 2026)
- ✅ Wake-on-LAN enabled (wol.service) — NIC doesn't retain standby power, but enabled as fallback (April 13, 2026)
- ✅ Filebrowser removed — unused, container and UFW rule deleted (March 14, 2026)
- ✅ Syncthing orphaned volume removed — `docker_syncthing_config` (March 14, 2026)
- ✅ Pi-hole real client IPs — DNAT rules bypass Docker proxy, Pi-hole sees actual device IPs (March 15, 2026)
- ✅ Pi-hole static IP pinned — `172.18.0.53` on management network (March 15, 2026)
- ✅ Pi-hole Docker port 53 publishing removed — DNAT in before.rules handles routing (March 15, 2026)
- ✅ Pi-hole listening mode set to ALL — required for cross-subnet DNAT queries, via `pihole-FTL --config` (v6) (March 15, 2026)
- ✅ Router DHCP DNS set to manual `192.168.1.10` — all devices now query Pi-hole directly with real IPs (March 15, 2026)
- ✅ Pi-hole blocklists expanded — 10 active lists, 671k+ domains blocked, 66 whitelisted, 27 blacklisted (March 15, 2026)
- ✅ Portainer removed — unused, CLI preferred (March 16, 2026)
- ✅ Uptime Kuma removed — unnecessary for home server (March 16, 2026)
- ✅ Homer dashboard updated — flat layout, removed dead links (March 16, 2026) — Homer removed (April 12, 2026)
- ✅ Nextcloud removed — replaced by Samba, data migrated to /mnt/storage/files/ (March 29, 2026)
- ✅ MariaDB removed — Nextcloud dependency (March 29, 2026)
- ✅ Redis removed — Nextcloud cache (March 29, 2026)
- ✅ Samba setup — LAN-only file sharing, home + files shares (March 29, 2026)
- ✅ UFW updated — port 8080 removed, Samba ports 445/139/137/138 added LAN-only (March 29, 2026)
- ✅ Docker compose cleaned — nextcloud network removed, nginx pinned to management only (March 29, 2026)
- ✅ Backup script — removed Nextcloud/MariaDB steps, added smb.conf to backup list (March 29, 2026)
- ✅ Backup system working — weekly compressed backup to HDD, root crontab, DB dump, 4-week retention (March 17, 2026)
- ✅ ntfy self-hosted — push notification server, Docker container on management network, LAN-only port 8083 (April 11, 2026)
- ✅ nginx-watcher — real-time log monitor with security alerts via ntfy, systemd service (April 11, 2026)
- ✅ Stale SSL cron removed from root crontab — correct version runs in user crontab (March 17, 2026)
- ✅ Laptop pull-backup script — manual SCP of latest backup via `pull-backup.sh` (March 17, 2026)
- ✅ Pi-hole removed — moved to N-server, DNAT/FORWARD rules cleaned, UFW ports 53/8081 removed, volumes deleted, router DNS updated (April 12, 2026)
- ✅ Homer removed — unused dashboard, UFW port 8082 removed, config directory deleted (April 12, 2026)
- ✅ pihole-setup.sh deleted — no longer needed on X-server (April 12, 2026)
- ✅ WireGuard VPN — native install, key-based auth, split tunnel, masquerade for full LAN access (April 12, 2026)
- ✅ UFW updated — port 51820/udp public, SSH/ntfy/Samba open to VPN subnet 10.0.0.0/24 (April 12, 2026)
- ✅ WireGuard forward rules — wg0 ↔ enp3s0 forwarding in `/etc/ufw/before.rules` (April 12, 2026)
- ✅ ntfy public access — nginx reverse proxy at `ntfy.example.net` with WebSocket/SSE support, TLS (April 13, 2026)
- ✅ ntfy auth — `auth-default-access: deny-all`, token-based auth, `behind-proxy: true` (April 13, 2026)
- ✅ nginx-watcher updated — bearer token auth for ntfy (April 13, 2026)
- ✅ ntfy-send.sh — shared notification helper script used by all monitoring scripts (April 13, 2026)
- ✅ server-health.sh — disk space + container monitoring every 10 min via cron (April 13, 2026)
- ✅ daily-summary.sh — morning briefing notification at 8 AM via cron (April 13, 2026)
- ✅ boot-notify.service — systemd oneshot sends ntfy notification on server boot (April 13, 2026)
- ✅ Backup cron — notifies on success/failure via ntfy (April 13, 2026)
- ✅ SSL renewal cron — notifies on success/failure via ntfy (April 13, 2026)
- ✅ Hibernate setup — swap resized to 6GB, GRUB resume params configured, `systemctl hibernate` working (April 13, 2026)
- ✅ Samba VPN access — removed `bind interfaces only` (Samba ignores wg0 with it enabled), added `10.0.0.0/24` to `hosts allow`, accessible via `\\10.0.0.1\` over WireGuard (April 13, 2026)
- ✅ Wake-on-LAN enabled — `wol.service` oneshot re-applies `ethtool -s enp3s0 wol g` on boot (April 13, 2026)
- ✅ Power watchdog — `power-watchdog.service` monitors AC/battery, hibernates at 15% battery with 30-min rtcwake cycle for automatic resume (April 13, 2026)
- ✅ SSH VPN access — added `ListenAddress 10.0.0.1` to sshd_config, SSH now accessible over WireGuard VPN (April 14, 2026)
- ✅ Server command listener — `server-cmd.py` subscribes to ntfy `server-cmd` topic for remote management from phone: ban/unban IPs, server status, attack summary, restart services, hibernate (April 14, 2026)
- ✅ Sudoers for server-cmd — `/etc/sudoers.d/server-cmd` allows passwordless `wg show`, `systemctl hibernate`, `systemctl restart nginx-watcher` (April 14, 2026)
- ✅ Security audit — Docker FORWARD rules tightened to DNS/HTTP/HTTPS only, blanket outbound removed (April 14, 2026)
- ✅ ntfy token centralized — moved from hardcoded in 3 scripts to `~/.config/ntfy-token.env` (mode 600), loaded via EnvironmentFile/source (April 14, 2026)
- ✅ Script permissions hardened — server-cmd.py, nginx-watcher.py, ntfy-send.sh set to mode 700 (April 14, 2026)
- ✅ AIDE file integrity monitoring — custom config (99_x-server), daily cron with ntfy alerts, default heavy scans disabled (April 14, 2026)
- ✅ Syslog forwarding to n-server — rsyslog TCP 514, per-program logs in /var/log/remote/x-server/, 8-week rotation (April 14, 2026)
- ✅ Stale credentials cleanup — /root/.backup-secrets deleted (April 14, 2026)
- ✅ Backup script fixed — removed stale references to .backup-secrets, Homer, and Nextcloud; added systemd services, sudoers, root crontab, AIDE config, rsyslog config, ntfy config to backup scope; added archive integrity verification (April 30, 2026)
- ✅ AIDE database rebuilt — baseline updated after April 14 hardening changes; future alerts reflect clean state (April 30, 2026)
- ✅ KidsApp deployed — Node.js/Express children's platform for a family member, Docker container on management network, reverse-proxied via nginx (May 7, 2026)
- ✅ KidsApp SSL — `kids.example.net` Let's Encrypt cert, auto-renews with all other certs (May 7, 2026)
- ✅ KidsApp CI/CD — GitHub Actions self-hosted runner, push-to-main auto-deploys with health check (May 7, 2026)
- ✅ KidsApp non-root hardened — container runs as `node` user (UID 1000), database chowned to match (May 7, 2026)
- ✅ KidsApp named volume confirmed — `docker_kids-app-data` for SQLite database, survives rebuilds (May 7, 2026)
- ✅ Portfolio moved off x-server — `example.com` + `www` now on Cloudflare Workers (Static Assets), DNS moved Namecheap → Cloudflare nameservers. Motivated by solar power cuts killing this box every 1–4 days; verified by powering x-server off with the site still serving. Container + duckdns vhost kept as rollback (August 8, 2026)

---

## 🔑 KEY LEARNINGS

- Docker bypasses UFW — always set `"iptables": false` in daemon.json
- Defense in depth: strong passwords + firewall + service binding + Docker isolation
- Nginx virtual hosts allow multiple sites on one IP
- Let's Encrypt + DuckDNS = free HTTPS
- Security headers matter — easy wins for web hardening
- Rate limiting protects against basic DDoS and brute force
- Always test security changes from outside the network
- Bind services to specific IPs, never 0.0.0.0
- Shell heredocs can mangle nginx configs — always verify before restart
- Nginx needs `include mime.types` or CSS is served as plain text
- `"iptables": false` kills container outbound too — need manual NAT/FORWARD rules in `/etc/ufw/before.rules`
- Docker Compose creates its own bridge networks (`br-*`) — rules targeting `docker0` won't work for Compose containers
- UFW's FORWARD chain drops packets before manually appended iptables rules — put rules in `before.rules` instead
- Always check which Docker network a container is on before debugging connectivity
- Syria blocks many CDN/GitHub domains — Pi-hole blocklist downloads, Telegram API, etc. may need proxies
- Docker volumes mounted as `:ro` can't have subdirectories created inside them — mount friend sites to a separate path (`/usr/share/nginx/sites/`)
- `docker run --rm` uses the default `docker0` bridge, not Compose networks — use `--network docker_management` for certbot and any container that needs outbound access
- Let's Encrypt `certbot/conf/live/` is root-owned — use `sudo test -d` to check for existing certs in scripts
- Use `--keep-until-expiring` with certbot to avoid interactive prompts in scripts
- Docker's userland proxy does SNAT — nginx sees `172.18.0.1` instead of real client IPs. Use DNAT rules in before.rules to bypass it
- Use `driver_opts: com.docker.network.bridge.name` in docker-compose to give bridges stable names that survive `docker compose down && up`
- Pin container IPs with `ipv4_address` in docker-compose when DNAT/FORWARD rules depend on them — pick high IPs (e.g. `.100`) to avoid collisions with DHCP-assigned IPs
- When removing Docker port publishing, `sudo iptables -t nat -F PREROUTING` may be needed to flush stale rules before `ufw reload`
- Nginx `map {}` blocks don't allow double-quoted regex patterns — causes "invalid number of the map parameters" error
- Nginx PCRE2 rejects `\.\.\\` as incomplete escape — use separate patterns for each traversal variant instead
- Check cert volume mount paths in docker-compose before writing nginx config — `/etc/letsencrypt/` vs `/etc/nginx/certbot-conf/` depends on your compose volumes
- A static site returning 200 to attack payloads (SQLi, SSTI, path traversal) tells scanners it's a live target — filter query strings and return 403 even if there's no real vulnerability
- Your own public IP can appear as an "attacker" in logs — hairpin NAT causes this
- `docker compose restart` does NOT pick up new volume mounts — use `docker compose up -d` to recreate the container
- `docker compose restart` stops and starts the container — if nginx fails to start (bad config), your site goes down. Use `docker compose exec nginx nginx -s reload` instead for zero-downtime reloads
- `docker run --rm` for nginx config testing fails if you don't mount all volumes (certs, sites, etc.) — use `docker compose exec nginx nginx -t` on the running container instead
- Always use `-T` flag with `docker compose exec` in cron jobs and scripts — without it, exec expects an interactive terminal
- CSP `script-src` blocks inline `onload="..."` event handlers — use a plain `<link rel="stylesheet">` instead of the async preload trick, or use SHA-256 hashes for inline scripts
- CSP needs both `style-src` (for CSS files) and `font-src` (for .woff2 files) whitelisted separately — Google Fonts uses `fonts.googleapis.com` for CSS and `fonts.gstatic.com` for font files
- Browser caches CSP headers aggressively — always hard-refresh (Ctrl+Shift+R) or use incognito after changing CSP
- Nginx `docker logs` are lost when container is recreated (`up -d`) — mount `/var/log/nginx` to a host directory for persistent logs
- Pi-hole v6 replaced env vars with `pihole-FTL --config` — `DNSMASQ_LISTENING` env var is silently ignored in v6
- Pi-hole's dnsmasq in `LOCAL` listening mode silently drops queries from different subnets — set `dns.listeningMode` to `all` when using DNAT (queries arrive from `192.168.1.x` to a `172.18.0.x` container)
- Same DNAT pattern works for Pi-hole as nginx — pin static IP, remove Docker port publishing, add PREROUTING + FORWARD rules for both UDP and TCP
- DNS uses both UDP (normal queries) and TCP (large responses, zone transfers) — DNAT rules need both protocols, unlike HTTP which is TCP only
- When applying DNAT changes, flush stale PREROUTING rules first (`sudo iptables -t nat -F PREROUTING`) before `ufw reload` — leftover rules from Docker port publishing cause silent conflicts
- Nextcloud is overkill for a single-user home server on weak hardware — 3 containers (app + MariaDB + Redis) for file storage is wasteful; Samba does the same with zero containers
- Samba has its own password store separate from Linux — must run `smbpasswd -a` even for existing Linux users, then `smbpasswd -e` to enable
- Samba doesn't reliably bind to WireGuard interfaces (`wg0`) — `bind interfaces only = yes` causes Samba to ignore the VPN interface even when listed; remove it and rely on `hosts allow` + UFW instead
- `hosts allow` + UFW is sufficient Samba security without `bind interfaces only` — as long as port 445 is not forwarded publicly, there is no exposure
- rsync interrupted by SSH disconnect is safe to re-run — it resumes from where it left off, only transferring missing files
- Always run long transfers inside `tmux` to survive SSH disconnects (`tmux new -s transfer`)
- Nextcloud stores data under a double `data/data/` path — actual user files are at `nextcloud/data/data/<user>/files/`, not `nextcloud/data/<user>/files/`
- Backup scripts needing `sudo` in cron fail (no TTY for password prompt) — run the script from root's crontab instead of adding NOPASSWD rules
- Always update `backup.sh` when removing services — stale references to deleted files or containers cause a FATAL exit, silently failing all subsequent backups
- Run WireGuard natively on the host, not in Docker — `iptables: false` makes Docker VPN networking painful; native WireGuard is just a kernel interface
- WireGuard silently drops unauthenticated packets — port scanners see the port as closed, no Fail2ban needed
- VPN clients get a different subnet (10.0.0.x) — UFW rules for LAN services must also allow `10.0.0.0/24` or VPN clients get blocked
- WireGuard masquerade (`POSTROUTING -s 10.0.0.0/24 -o enp3s0 -j MASQUERADE`) makes VPN traffic appear as the server's LAN IP to other devices — without it, other LAN devices don't know how to reply to 10.0.0.x
- Same UFW FORWARD problem as Docker — WireGuard masquerade alone isn't enough, need explicit forward rules in `/etc/ufw/before.rules` for wg0 ↔ enp3s0
- One key pair per client — never reuse keys; revoking a compromised device is just removing its `[Peer]` block
- Reverse-proxy LAN services through nginx for WAN access instead of always-on VPN — saves phone battery, works on any network
- ntfy WebSocket reverse proxy needs a `map` for the `Connection` header — hardcoding `Connection "upgrade"` breaks non-WebSocket requests; use `map $http_upgrade $connection_upgrade` to conditionally set it
- ntfy `auth-file` path must exist inside the container — use an already-mounted volume path (e.g. `/var/cache/ntfy/user.db`) instead of creating new directories
- Set `behind-proxy: true` in ntfy when behind nginx — without it, ntfy sees nginx's IP instead of real clients
- Chicken-and-egg with certbot + nginx: add the HTTP server block first (ACME challenge only), reload nginx, get the cert, then add the HTTPS block
- `certbot renew` handles all certs in `/etc/letsencrypt` — no per-domain cron needed, one renewal cron covers everything
- `docker inspect` uses the container name, not the service name — if Compose names it `nginx-ssl`, health checks must use that exact name
- Wrap cron jobs with `&& notify success || notify failure` to catch silent failures — backups and cert renewals can fail for weeks without anyone noticing
- `systemctl is-active` returns the status string AND a non-zero exit code for inactive services — `|| echo "inactive"` causes double output; just capture the output directly
- Hibernate needs swap ≥ RAM size — 4GB swap can't hibernate 5.6GB RAM; resize to 6GB
- Hibernate on non-EFI systems requires `resume=` and `resume_offset=` in GRUB kernel params — without them, `systemctl hibernate` fails with "No available method to resume"
- Get swap file offset with `filefrag -v /swap.img` — first `physical_offset` value goes into GRUB's `resume_offset=`
- WoL (`ethtool -s enp3s0 wol g`) doesn't survive reboots — needs a systemd oneshot service to re-apply on every boot
- WoL support (`Supports Wake-on: pumbg`) doesn't mean WoL works — the NIC must retain standby power after shutdown; HP G62 NIC loses power completely
- `rtcwake -m disk` can wake from hibernate on a schedule — useful as a workaround when WoL/wake-on-AC aren't supported
- Old laptop batteries are terrible UPSes — don't wait for 10% to hibernate; the battery might die faster than expected
- Hibernate resumes SSH sessions, Docker containers, and all state — much better than a cold boot after hard crash
- ACPI wake from suspend (`systemctl suspend`) on charger plug-in is hardware-dependent — HP G62 doesn't support it
- sshd `ListenAddress` limits which interfaces accept connections — to allow VPN access, add the VPN interface IP (`10.0.0.1`) as a second `ListenAddress`
- ntfy's JSON stream API (`/topic/json`) is ideal for building command listeners — subscribe with `stream=True` in requests, parse each line as JSON
- Use tightly scoped sudoers rules (`/etc/sudoers.d/`) for scripts that need specific root commands — never give broad NOPASSWD access
- `free -h` outputs human-readable units (Mi, Gi) that break awk arithmetic — use `free -m` for numeric processing
- Docker container outbound should be restricted per-port in FORWARD rules, not blanket ACCEPT — if a container is compromised, you don't want arbitrary outbound
- Never hardcode secrets in scripts — use environment files (mode 600) loaded via systemd EnvironmentFile or shell source
- AIDE default Ubuntu config scans the entire filesystem — disable the 70_*/99_aide_root configs and write a custom rule file for only your critical paths, or aideinit will take hours on weak hardware
- rsyslog forwarding config must only exist on the sender, not the receiver — creating it on both sides causes an infinite loop that bloats syslog
- After any intentional change to AIDE-monitored files, rebuild the database: `sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db`
- Samba listens on 0.0.0.0 even without `bind interfaces only` — defense comes from UFW (subnet-scoped rules) + `hosts allow` (two independent layers)
- `node:18-alpine` includes a built-in `node` user (UID 1000) — no need to `adduser`, just `USER node` in Dockerfile
- `VOLUME /data` in a Dockerfile creates an anonymous volume if docker-compose doesn't define a named one — anonymous volumes get orphaned on `docker compose down` or `docker system prune`
- `docker volume inspect <name>` uses the Compose project-prefixed name (e.g. `docker_kids-app-data`, not `kids-app-data`) — check with `docker volume ls | grep <name>`
- Files created as root in a Docker volume stay root-owned even after switching to a non-root `USER` — `chown` the volume contents after changing the runtime user
- `DOCKER_BUILDKIT=0` is needed on this server for two reasons: BuildKit has a silent `npm ci` bug and doesn't support `--network` for build-time container network access
- Groq API (`api.groq.com`) is blocked in Syria just like Telegram — proxy AI calls through a Cloudflare Worker
- CSP for reverse-proxied apps: let the app handle its own CSP via Helmet (or equivalent) — adding CSP in nginx produces duplicate headers that break things
- GitHub Actions self-hosted runner on a Syria server must be installed manually (CDN blocked) — the `.runner` config file confirms installation
- Never verify a DNS cutover with a bare `curl` from WSL — the local resolver cache reported the old origin (`server: nginx`) for a long time after `example.com` moved to Cloudflare, twice. `curl --resolve <host>:443:<new-ip>` is the only answer you can trust
- A domain leaving this server has to leave the certbot `-d` list too — HTTP-01 webroot needs DNS pointing here, so a moved domain turns into a weekly failing renewal and a false ntfy alert

---

## 📚 REFERENCE

- Ubuntu Server: https://ubuntu.com/server/docs
- Docker: https://docs.docker.com
- Nginx: https://nginx.org/en/docs/
- Let's Encrypt: https://letsencrypt.org/docs/
- DuckDNS: https://app.example.net
- Pi-hole: https://docs.pi-hole.net
- WireGuard: https://www.wireguard.com
- Security Headers: https://securityheaders.com
- r/selfhosted: https://reddit.com/r/selfhosted
