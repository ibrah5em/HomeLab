# LAN server — full runbook

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
- HP laptop (Intel i3-2370M @ 2.40GHz, 3.7GiB RAM)
- 223.6GB SSD (sda) — Ubuntu 24.04.4 LTS
- No HDD — SSD only
- Location: Near router, headless (no monitor, screen off)

---

## 🌐 NETWORK CONFIGURATION

**Local Network:**
- **Hostname:** n-server
- **Ethernet IP:** 192.168.1.11 (static, reserved in router)
- **MAC Address:** <MAC> (reserved in <router-model> DHCP)
- **Interface:** enp9s0
- **Router:** <router-model>

**No public internet exposure** — all services are LAN-only. No ports forwarded on router for n-server.

**DNS Role:**
- **Router DHCP DNS:** Manual, set to `192.168.1.11` (Pi-hole) — all devices on the network query n-server for DNS

---

## 🔒 SECURITY CONFIGURATION

### SSH
- **Port:** 2222 (changed from 22)
- **Bound to:** 192.168.1.11 only (not accessible from internet)
- **Authentication:** SSH keys only (passwords disabled)
- **Key type:** Ed25519 (`n-server`)
- **Root login:** Disabled
- **User:** homelab
- **Connection:** `ssh n-server` (via SSH config)
- **Socket-based SSH masked** — `ssh.socket` masked (not just disabled), `ssh.service` enabled and starts on boot

**Laptop SSH config (`~/.ssh/config`):**
```
Host n-server
    HostName 192.168.1.11
    User homelab
    Port 2222
    IdentityFile ~/.ssh/n-server
    ServerAliveInterval 60
```

### Firewall (UFW)

```
Status: active
Default: deny (incoming), allow (outgoing)

To                         Action      From
--                         ------      ----
2222/tcp                   ALLOW IN    192.168.1.0/24   # SSH
445/tcp                    ALLOW IN    192.168.1.0/24   # Samba
139/tcp                    ALLOW IN    192.168.1.0/24   # Samba (NetBIOS)
3000/tcp                   ALLOW IN    192.168.1.0/24   # Gitea
80/tcp                     ALLOW IN    192.168.1.0/24   # Pi-hole web UI
53                         ALLOW IN    192.168.1.0/24   # DNS (Pi-hole)
514/tcp                    ALLOW IN    192.168.1.0/24   # rsyslog from x-server
8000/tcp                   ALLOW IN    192.168.1.0/24   # pyLoad webui (LAN + VPN)
```

> The `8000/tcp` rule is scoped to the LAN subnet only — yet VPN clients reach it
> too. WireGuard on x-server masquerades `10.0.0.0/24` out its LAN interface, so
> VPN traffic arrives at n-server already sourced from `192.168.1.10` (inside
> `192.168.1.0/24`). No separate `10.0.0.0/24` rule is needed. Never widen this to
> WAN — n-server stays dark.

### Other Security
- ✅ Fail2ban (3 failed attempts = 1 hour ban on SSH)
- ✅ Automatic security updates (unattended-upgrades)
- ✅ Password authentication disabled
- ✅ Root login disabled
- ✅ Lid close → server stays running (HandleLidSwitch=ignore)
- ✅ Power button → screen toggle (HandlePowerKey=ignore, handled by acpid)
- ✅ Screen off on boot via systemd (intel_backlight)
- ✅ Screen off on lid close via acpid
- ✅ Disabled unnecessary services: ModemManager, fwupd, multipathd
- ✅ `gitea` system user shell set to `/usr/sbin/nologin` (hardened April 30, 2026)
- ✅ `systemd-resolved` disabled and masked — prevents port 53 conflicts with Pi-hole (April 30, 2026)

---

## 🐳 SERVICES

All services run bare metal (no Docker).

### Running Services

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| **SSH** | 2222 | 🏠 LAN only | Remote shell |
| **Samba** | 445, 139 | 🏠 LAN only | Windows file sharing |
| **Gitea** | 3000 | 🏠 LAN only | Self-hosted Git server |
| **Pi-hole** | 53 (DNS), 80 (web UI) | 🏠 LAN only | Network-wide ad blocker & DNS |
| **rsyslog receiver** | 514 (TCP) | 🏠 LAN only | Remote log storage for x-server |
| **Gitea Actions runner** | — (outbound poll → :3000) | 🏠 LAN only | `act_runner` v0.2.11, host mode — auto-deploys the HomeLab repo |
| **pyLoad** | 8000 (web UI) | 🏠 LAN + VPN | Download manager (direct HTTP/FTP + file hosters). `pyload-ng` via pipx, systemd `pyload.service`. Downloads land in `~/Downloads` = the `n-server-home` Samba share |

### Planned Services

| Service | Port | Status |
|---------|------|--------|
| **WireGuard** | 51820/udp | 📋 Future Phase |

---

## 📁 SAMBA (Windows File Sharing)

Exposes `/home/homelab/Downloads` as a network drive on Windows (the share name is
historically `n-server-home`, but its path is the Downloads folder, **not** the whole
home dir — keeping `~/.ssh`, dotfiles, etc. off the share). This is also where pyLoad
drops completed downloads, so they appear on the share automatically.

### Access from Windows
Open File Explorer → address bar:
```
\\192.168.1.11\n-server-home
```
Login: username `homelab` + Samba password.

To make it a permanent drive letter: right-click "This PC" → Map network drive → paste path above.

### Config
```
/etc/samba/smb.conf — share: [n-server-home]
Path: /home/homelab/Downloads
Valid users: homelab
```

### Commands
```bash
# Restart Samba
sudo systemctl restart smbd nmbd

# Change Samba password
sudo smbpasswd homelab

# Check status
sudo systemctl status smbd
```

---

## ⬇️ PYLOAD (Download Manager)

Web-based download manager for **direct HTTP/FTP links and file hosters** (not a
torrent client). Chosen over JDownloader specifically because it is **fully
self-hosted**: you reach its own web UI directly over LAN/VPN, with nothing routed
through a third-party cloud relay (JDownloader's MyJDownloader app would relay via
`my.jdownloader.org` — a needless dependency for a dark-to-WAN box, and a likely
Syria-block target). Downloads land in `~/Downloads`, which is the `n-server-home`
Samba share, so finished files show up on the Windows mapped drive immediately.

### Access
```
Web UI:   http://192.168.1.11:8000        (LAN, or over WireGuard VPN)
Login:    admin / <password stored in your password manager>
```
- **Mobile:** open the URL in the phone browser → "Add to Home Screen" to install it
  as a PWA. The UI is responsive; there is no separate native app.
- **Remote (off home Wi-Fi):** connect the WireGuard VPN first, then the same
  `192.168.1.11:8000` URL works (see the firewall note above for why).

### Setup details
- Installed with **pipx** as user `homelab`: `pipx install pyload-ng` → binary at
  `~/.local/bin/pyload` (pipx venv under `~/.local/share/pipx/venvs/pyload-ng/`).
- Runs as a systemd **system** service `pyload.service` (User=homelab), bound to
  `0.0.0.0:8000`, with `--storagedir ~/Downloads`. Hardened with `NoNewPrivileges`,
  `PrivateTmp`, `ProtectSystem=full`.
- `pyload-ng` ships a default `pyload/pyload` login. It was removed: the user was
  renamed to `admin` and a strong password set. `pyload --reset` only resets back to
  the *default* creds (it does not prompt for custom ones), so the password is set by
  writing the PBKDF2-HMAC-SHA256 hash (`salt[16B] + dk[32B]`, 100k iters) directly
  into `~/.pyload/data/pyload.db` while the service is stopped. To rotate it, repeat
  that, or use the web UI's user management.

### Key paths
```
Config:        ~/.pyload/settings/pyload.cfg     (webui host=0.0.0.0, debug off)
User DB:       ~/.pyload/data/pyload.db          (users, packages, links — hashed pw here)
Logs:          ~/.pyload/logs/pyload.log
Downloads:     ~/Downloads                       (= n-server-home Samba share)
systemd unit:  /etc/systemd/system/pyload.service
Repo copies:   ~/HomeLab/configs/n-server/{systemd/pyload.service, pyload/pyload.cfg}
```

### Commands
```bash
sudo systemctl status pyload          # service state
sudo systemctl restart pyload         # restart (e.g. after a config edit)
journalctl -u pyload -f               # live logs
ss -tlnp | grep :8000                 # confirm it's listening
```

> The repo copy of `pyload.cfg` is a track-only reference (no deploy section for it).
> `pyload.service` **is** deployed by `configs/n-server/deploy.sh` (systemd section),
> md5-gated — so the committed unit must stay identical to the server's.

---

## 🐙 GITEA

Self-hosted Git server. Used as the primary remote for all personal projects.

### Access
```
Web UI:  http://192.168.1.11:3000
```

### Setup details
- **Binary:** `/usr/local/bin/gitea`
- **User:** `gitea` (system user, shell: `/usr/sbin/nologin`)
- **Data directory:** `/var/lib/gitea/`
- **Config:** `/etc/gitea/app.ini`
- **Database:** SQLite3 (stored in `/var/lib/gitea/data/`)
- **Bare repos:** `/var/lib/gitea/data/gitea-repositories/<owner>/<repo>.git`
  (`ROOT` in `app.ini`) — note it's under `data/`, **not** `/var/lib/gitea/repositories/`.
  Owner and repo names are lowercased on disk regardless of their display case.
- **Account password:** `$GITEA_PASSWORD` in `~/.server-creds.env` on WSL (rotated 2026-08-05).
  See `~/HomeLab/.claude/CLAUDE.md` for the credential-helper pattern.

### Key config (`/etc/gitea/app.ini`)
```ini
[server]
SSH_DOMAIN   = 192.168.1.11
DOMAIN       = 192.168.1.11
HTTP_PORT    = 3000
ROOT_URL     = http://192.168.1.11:3000/
OFFLINE_MODE = true
```

### Commands
```bash
# Restart
sudo systemctl restart gitea

# Logs
sudo journalctl -u gitea -f

# Status
sudo systemctl status gitea
```

### Server-side git maintenance (purging secrets from history)

**Always run git in a bare repo as the `gitea` user, never as root.** As root it fails
with `detected dubious ownership`, and any object it *does* write lands root-owned —
which silently breaks Gitea's own pushes later.

```bash
R=/var/lib/gitea/data/gitea-repositories/homelab/<repo>.git
sudo -u gitea git -C $R for-each-ref              # what the server actually has
sudo -u gitea git -C $R count-objects -vH
```

A force-push only moves refs — the old objects stay fetchable by hash until the reflog is
expired and the repo is gc'd. That server-side step is the one that reclaims the blob:

```bash
sudo -u gitea git -C $R reflog expire --expire=now --all
sudo -u gitea git -C $R gc --prune=now
```

To *verify* a purge rather than assume it, scan every object in the store — reachability
isn't the question, presence is:

```bash
# does any tree still name the file?
sudo -u gitea git -C $R cat-file --batch-all-objects --batch-check='%(objecttype) %(objectname)' \
  | awk '$1=="tree"{print $2}' | while read t; do sudo -u gitea git -C $R ls-tree $t | grep -i '<filename>'; done
sudo -u gitea git -C $R fsck --unreachable        # should print nothing after gc
```

Done for `<research-repo>` on 2026-08-05 (Keycloak recovery codes +
an old Gitea password): 699 objects / 26.6 MiB → 385 / 13.9 MiB, both cleartext blobs gone.
**Rotate the exposed credential first** — the purge closes the hole, rotation is what makes
the leaked value worthless in the meantime.

### Git workflow (from main laptop / WSL)
```bash
# Add Gitea as primary remote
git remote add origin http://192.168.1.11:3000/homelab/REPO.git

# Push to Gitea (primary)
git push origin master

# Push to GitHub (public mirror, when needed)
git push github master
```

Save credentials so you're not asked every time:
```bash
git config --global credential.helper store
```

Use a **personal access token** (not your password) when pushing over HTTP:
```
http://192.168.1.11:3000/user/settings/applications
```

---

## 🤖 GITEA ACTIONS RUNNER (Auto-Deploy)

`act_runner` on n-server watches the HomeLab repo and auto-deploys it. A push to
`main` that touches `configs/`, `scripts/`, or `crontabs/` paths fires the matching
workflow, which syncs the local deploy mirror to the pushed commit and runs
`configs/<server>/deploy.sh` — SSHing into x-server and/or n-server.

> ⚠️ **Trust model:** anyone who can push to `main` can run arbitrary `sudo` on
> both servers. The mitigation is the branch-then-merge discipline — work lands on
> a topic branch and only reaches `main` after review. Don't relax it. See CLAUDE.md.

### Setup details
- **Binary:** `/usr/local/bin/act_runner` — v0.2.11 (pinned to match Gitea 1.23.5)
- **Mode:** host mode (no Docker on n-server) — label `ubuntu-latest:host`
- **Config:** `~/config.yaml` — generated from the pinned binary, then trimmed (cache off, single host label, 5m graceful shutdown drain so a restart doesn't sever a deploy mid-sudo)
- **Registration:** `~/.runner` (id 1, name `n-server`)
- **Service:** `act-runner.service` — `ExecStart=/usr/local/bin/act_runner daemon -c /home/homelab/config.yaml`
  > Tracked at `configs/n-server/systemd/act-runner.service`. `deploy.sh` daemon-reloads a changed unit but does **NOT** auto-restart it (the deploy may run inside the runner) — restart by hand: `ssh n-server 'sudo systemctl restart act-runner'`.

### What the runner needs on n-server (bootstrap)
- `~/.ssh/config` — `x-server` + `n-server` Host aliases (Port 2222, `IdentityFile ~/.ssh/homelab-deploy`, `IdentitiesOnly yes`)
- `~/.ssh/known_hosts` — pre-seeded for both servers on Port 2222
- `~/HomeLab` — deploy mirror clone; the workflow `git fetch`es and force-checks-out the pushed SHA here (ends up detached HEAD, by design)
- `~/.git-credentials` — Gitea HTTP token (mirrors the WSL setup) so the mirror fetch is silent
- The `homelab-deploy` **pubkey** in `authorized_keys` on **both** servers (n-server too, for the loopback `ssh n-server` that `deploy.sh` uses for every section). The **private** key is never persisted — the workflow materializes it per-run and wipes it in `if: always()`.

### Workflows (in the repo)
```
.gitea/workflows/deploy-x-server.yml   ← paths: configs/x-server/**, scripts/x-server/**, crontabs/x-server.*
.gitea/workflows/deploy-n-server.yml   ← paths: configs/n-server/**, scripts/n-server/**, crontabs/n-server.*
```
Each: concurrency-gated (queue, never cancel a deploy mid-flight), 15m timeout,
force-checkout to `github.sha` (no drift if commits land mid-run), deploy key
materialized per-run + wiped in `if: always()`, ntfy ping to `security-alerts`
(LAN container `http://192.168.1.10:8083`) on success/failure. Gitea filters
`paths` per-workflow (not per-job) — hence one file per server. Both also expose
`workflow_dispatch`.

### Secrets (Gitea repo secrets)
`X_SERVER_SUDO`, `N_SERVER_SUDO`, `DEPLOY_SSH_KEY`, `NTFY_TOKEN`. Set via the API:
```bash
curl -X PUT -H "Authorization: token <PAT>" -H "Content-Type: application/json" \
  -d '{"data":"<value>"}' \
  http://192.168.1.11:3000/api/v1/repos/homelab/homelab/actions/secrets/<NAME>
```
> `DEPLOY_SSH_KEY` must end with a trailing newline or ssh rejects it as "invalid format".

### Commands
```bash
# Runner service
sudo systemctl status act-runner.service
sudo journalctl -u act-runner.service -f

# Trigger a manual run: web UI only (Gitea 1.23.5 has no dispatch API), or push a
# commit that matches a workflow's path filter.

# Poll run status (PAT works on /api/ routes, not the HTML pages)
curl -s -H "Authorization: token <PAT>" \
  http://192.168.1.11:3000/api/v1/repos/homelab/homelab/actions/tasks?limit=5
```

---

## 🛡️ PI-HOLE (DNS & Ad Blocking)

Network-wide ad blocker. All devices on the LAN use n-server as their DNS server.

### Access
```
Web UI:  http://192.168.1.11/admin
```

### Setup details
- **Version:** v6.4.2 (Core), v6.5 (Web), v6.6.1 (FTL)
- **Install method:** Bare metal (official installer)
- **Upstream DNS:** 1.1.1.1, 8.8.8.8
- **Listening mode:** All interfaces
- **Rate limiting:** Disabled
- **Gravity DB:** Imported from x-server (Docker Pi-hole)
- **Blocklists:** ~621k unique domains (12 curated lists)
- **Whitelisted:** 67 domains
- **Blacklisted:** 40 domains
- **HTTPS:** Disabled — web UI on port 80 only (`webserver.port = 80`)

### Key config
- **Config file:** `/etc/pihole/pihole.toml`
- **Gravity DB:** `/etc/pihole/gravity.db`
- **FTL database:** `/etc/pihole/pihole-FTL.db`
- **Service:** `pihole-FTL`

### Commands
```bash
# Restart
sudo systemctl restart pihole-FTL

# Status
sudo systemctl status pihole-FTL

# Update Pi-hole (needs WARP — see update procedure below)
sudo pihole -up

# Update blocklists only
sudo pihole -g

# Live query log
pihole -t

# Check if domain is blocked
pihole -q <domain>

# Whitelist / blacklist
sudo pihole -w <domain>
sudo pihole -b <domain>

# Reset web password
sudo pihole setpassword

# Check config
pihole-FTL --config dns.upstreams
pihole-FTL --config dns.interface
pihole-FTL --config dns.listeningMode
```

### Pi-hole update procedure (Syria — needs WARP)
FTL is fetched from GitHub, which is blocked. Always follow this order:

```bash
# 1. Stop Pi-hole to free port 53
sudo systemctl stop pihole-FTL

# 2. Start WARP (use tmux — WARP can drop SSH sessions)
sudo systemctl start warp-svc
warp-cli connect

# 3. Update
sudo pihole -up

# 4. Disconnect WARP immediately
warp-cli disconnect
sudo systemctl stop warp-svc

# 5. Restart Pi-hole
sudo systemctl start pihole-FTL
```

### Router DNS config
Router DHCP DNS is set to `192.168.1.11` (n-server) — all devices query Pi-hole automatically.

### Important notes
- WARP grabs port 53 — conflicts with Pi-hole. Always stop `warp-svc` after use.
- WARP reroutes traffic including SSH — may drop active SSH sessions. Use `tmux` for long operations.
- WARP binds to a virtual interface (`172.16.0.x`) — not your LAN IP.
- Service is disabled by default (does not start on boot).
- Pi-hole v6 enables HTTPS (port 443) by default with a self-signed cert — disabled here, HTTP only.
- Update command is `pihole -up` (not `pihole update` which doesn't exist in v6).
- After any FTL restart, `systemd-resolved` may wake up and grab port 53 — FTL will fail with "Address in use". Fix: `sudo systemctl stop systemd-resolved && sudo systemctl restart pihole-FTL`. Permanently prevent with `sudo systemctl disable systemd-resolved && sudo systemctl mask systemd-resolved`.

---

## 📡 RSYSLOG REMOTE LOG RECEIVER (X-Server Forensic Logs)

N-server receives and stores syslog from x-server over TCP 514. If an attacker compromises x-server and wipes local logs, the copies on n-server survive.

### Config

**Receiver config:** `/etc/rsyslog.d/10-receive-x-server.conf`
```
# Listen for remote logs on TCP 514 (LAN only — UFW restricts access)
module(load="imtcp")
input(type="imtcp" port="514")

# Write x-server logs to a dedicated directory
template(name="RemoteHost" type="string" string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")

if $fromhost-ip == '192.168.1.10' then {
    action(type="omfile" dynaFile="RemoteHost")
    stop
}
```

- Filters by source IP — only `192.168.1.10` (x-server) gets written
- Logs organized per hostname and per program name under `/var/log/remote/`
- The `stop` directive prevents x-server messages from landing in n-server's own `/var/log/syslog`

**Log rotation:** `/etc/logrotate.d/remote-logs`
```
/var/log/remote/x-server/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
```
Weekly rotation, 8 weeks retained (compressed).

### Log locations
```
Remote log directory:     /var/log/remote/x-server/ (owned by syslog:adm)
Per-program log files:    sudo.log, kernel.log, systemd.log, sshd.log,
                          bash.log, NetworkManager.log, smartd.log,
                          CRON.log, postfix.log, python3.log, and more
                          (files appear per program that logs on x-server)
```

### Commands
```bash
# Check if logs are arriving from x-server
sudo ls -la /var/log/remote/x-server/

# Read x-server sudo activity
sudo cat /var/log/remote/x-server/sudo.log

# Read x-server kernel messages
sudo cat /var/log/remote/x-server/kernel.log

# Search for specific events across all x-server logs
sudo bash -c 'grep "search term" /var/log/remote/x-server/*'

# Check rsyslog receiver status
sudo systemctl status rsyslog
sudo ss -tlnp | grep 514

# Check disk usage of remote logs
sudo du -sh /var/log/remote/
```

### Incident response: if x-server is compromised

1. **Do NOT touch n-server's remote logs** — they're your evidence
2. Check `sudo.log` for unauthorized privilege escalation
3. Check `systemd.log` for unexpected service changes
4. Check all log files for the attacker's IP or unusual timestamps
5. The logs here predate any cleanup the attacker did on x-server

---

## 🌐 CLOUDFLARE WARP (GitHub CDN Bypass)

Cloudflare WARP is installed to bypass Syria's GitHub/CDN blocks. Used on-demand, not always-on.

### Usage
```bash
# Start WARP service
sudo systemctl start warp-svc

# Connect
warp-cli connect

# Do what you need (pihole -up, pihole -g, apt installs from GitHub, etc.)

# Disconnect when done
warp-cli disconnect
sudo systemctl stop warp-svc
```

### Important notes
- WARP grabs port 53 — conflicts with Pi-hole. Always stop `warp-svc` after use.
- WARP reroutes traffic including SSH — may drop active SSH sessions. Use `tmux` for long operations.
- WARP binds to a virtual interface (`172.16.0.x`) — not your LAN IP.
- Service is disabled by default (does not start on boot).
- When updating Pi-hole: stop pihole-FTL first, then start WARP, then update, then stop WARP, then restart pihole-FTL.

---

## 🔒 WIREGUARD VPN — FUTURE PHASE

When set up, WireGuard will allow access to the full LAN (x-server, n-server, Pi-hole) from anywhere.

### Plan
- **Server:** n-server (192.168.1.11)
- **VPN subnet:** 10.0.0.0/24
- **Port:** 51820/udp (needs router port forward)
- **DNS:** 192.168.1.11 (Pi-hole on n-server — ad blocking works remotely too)
- **Routing:** Split tunnel — only LAN traffic routed through VPN

### When ready, add UFW rule
```bash
sudo ufw allow 51820/udp
```

And forward UDP port 51820 → 192.168.1.11 on <router-model> router.

### Setup reference
See original n-server-setup.md Phase 4 for full instructions.

---

## 🌐 SERVICE ACCESS

### From LAN
```
SSH:              ssh n-server (Port 2222)
Samba:            \\192.168.1.11\n-server-home
Gitea:            http://192.168.1.11:3000
Pi-hole:          http://192.168.1.11/admin
```

### From Internet
```
Nothing exposed. Zero public-facing ports.
VPN access planned via WireGuard (future).
```

---

## 📁 IMPORTANT FILE LOCATIONS

```
SSH server config:         /etc/ssh/sshd_config
SSH client config:         ~/.ssh/config (on laptop)
SSH key (laptop):          ~/.ssh/n-server
Samba config:              /etc/samba/smb.conf
Gitea config:              /etc/gitea/app.ini
Gitea data:                /var/lib/gitea/
act_runner binary:         /usr/local/bin/act_runner
act_runner config:         ~/config.yaml
act_runner registration:   ~/.runner
act-runner systemd unit:   /etc/systemd/system/act-runner.service  (tracked: configs/n-server/systemd/)
Deploy mirror checkout:    ~/HomeLab
Pi-hole config:            /etc/pihole/pihole.toml
Pi-hole gravity DB:        /etc/pihole/gravity.db
Pi-hole FTL database:      /etc/pihole/pihole-FTL.db
Pi-hole install log:       /etc/pihole/install.log
UFW rules:                 /etc/ufw/
rsyslog receiver config:   /etc/rsyslog.d/10-receive-x-server.conf
Remote log rotation:       /etc/logrotate.d/remote-logs
Remote logs (x-server):    /var/log/remote/x-server/
logind config:             /etc/systemd/logind.conf
GRUB config:               /etc/default/grub
Scripts:                   ~/scripts/
Backups:                   ~/backups/
Downloads:                 ~/Downloads/
Screen-off service:        /etc/systemd/system/screen-off.service
acpid lid-close event:     /etc/acpi/events/lid-close
acpid lid-close script:    /etc/acpi/lid-close.sh
acpid power-btn event:     /etc/acpi/events/power-button
acpid power-btn script:    /etc/acpi/power-button.sh
```

### Home directory layout
```
~/
├── HomeLab/                           ← deploy mirror (Gitea Actions runner checks out here)
├── config.yaml                        ← act_runner config (host mode)
├── .runner                            ← act_runner registration (id 1)
├── backups/
│   ├── gitea-backup-20260411.tar.gz   ← Gitea backup from initial setup
│   └── gravity.db                     ← original gravity DB from x-server migration
├── Downloads/
└── scripts/
    ├── n-server-audit.sh              ← full system audit script
    └── backup.sh                      ← n-server backup pipeline (Gitea + Pi-hole snapshots)
```

---

## 🖥️ HEADLESS SETUP

### Lid close (server stays on)
`/etc/systemd/logind.conf`:
```
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandlePowerKey=ignore
```
> `HandlePowerKey=ignore` lets acpid handle the power button for screen toggling instead of shutting down.

### GRUB (no screen blank)
`/etc/default/grub`:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash consoleblank=0"
```

### Screen management (acpid + systemd)

Screen is controlled via `intel_backlight` — no `vbetool` needed.

**Turn screen off/on manually:**
```bash
# Off
echo 0 > /sys/class/backlight/intel_backlight/brightness

# On (restore full brightness)
cat /sys/class/backlight/intel_backlight/max_brightness | sudo tee /sys/class/backlight/intel_backlight/brightness
```

**screen-off.service** — turns screen off on every boot:
```ini
# /etc/systemd/system/screen-off.service
[Unit]
Description=Turn off screen on boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo 0 > /sys/class/backlight/intel_backlight/brightness'

[Install]
WantedBy=multi-user.target
```

**acpid lid-close** — turns screen off when lid is closed:
```bash
# /etc/acpi/events/lid-close
event=button/lid LID close
action=/etc/acpi/lid-close.sh
```
```bash
# /etc/acpi/lid-close.sh
#!/bin/bash
echo 0 > /sys/class/backlight/intel_backlight/brightness
```

**acpid power button** — toggles screen on/off (short press):
```bash
# /etc/acpi/events/power-button
event=button/power
action=/etc/acpi/power-button.sh
```
```bash
# /etc/acpi/power-button.sh
#!/bin/bash
current=$(cat /sys/class/backlight/intel_backlight/brightness)
if [ "$current" -eq 0 ]; then
    max=$(cat /sys/class/backlight/intel_backlight/max_brightness)
    echo $max > /sys/class/backlight/intel_backlight/brightness
else
    echo 0 > /sys/class/backlight/intel_backlight/brightness
fi
```

**Summary of screen behaviour:**
- **Boot** → screen off (systemd)
- **Lid close** → screen off (acpid)
- **Lid open** → screen stays off (no script fires — lid open is the emergency escape)
- **Power button short press** → toggles screen on/off (acpid)
- **SSH fails emergency** → open lid, screen comes on naturally for physical access

---

## 📋 QUICK REFERENCE

```
n-server IP:        192.168.1.11
MAC:                <MAC>
SSH:                ssh n-server (Port 2222)
Samba:              \\192.168.1.11\n-server-home
Gitea:              http://192.168.1.11:3000
Pi-hole:            http://192.168.1.11/admin
DNS:                192.168.1.11 (router DHCP primary)
OS:                 Ubuntu 24.04.4 LTS
```

---

## ✅ SETUP CHANGELOG

- ✅ Ubuntu 24.04.4 LTS installed
- ✅ SSH hardened — Port 2222, key auth only, LAN bound, ssh.socket disabled (March 28, 2026)
- ✅ UFW configured — deny incoming, LAN-only rules for all services (March 28, 2026)
- ✅ Samba installed — home folder shared as `n-server-home` (March 28, 2026)
- ✅ Fail2ban installed — SSH brute force protection (March 28, 2026)
- ✅ Unattended upgrades enabled — automatic security updates (March 28, 2026)
- ✅ Unnecessary services disabled — ModemManager, fwupd, multipathd (March 28, 2026)
- ✅ Lid close set to ignore — server stays running (March 28, 2026)
- ✅ Static IP reserved on router — MAC <MAC> → 192.168.1.11 (March 28, 2026)
- ✅ Gitea installed — self-hosted Git server on port 3000, SQLite backend (April 2, 2026)
- ✅ ssh.socket masked — prevents Ubuntu from re-enabling socket-based SSH on reboot (April 4, 2026)
- ✅ ssh.service enabled — ensures SSH starts automatically on boot (April 4, 2026)
- ✅ acpid installed — handles lid close and power button events (April 4, 2026)
- ✅ screen-off.service — turns screen off on boot via intel_backlight (April 4, 2026)
- ✅ Power button configured — short press toggles screen on/off, no shutdown (April 4, 2026)
- ✅ HandlePowerKey=ignore set in logind.conf — power button handed off to acpid (April 4, 2026)
- 🗑️ qBittorrent removed — closed only public-facing port (35358), reduced attack surface (April 12, 2026)
- 🗑️ Vaultwarden + Caddy removed — unused, replaced by KeePassXC + Syncthing (April 12, 2026)
- ✅ Cloudflare WARP installed — bypasses Syria's GitHub/CDN blocks on demand (April 12, 2026)
- ✅ Pi-hole installed — bare metal, v6.4.1, network-wide DNS ad blocker (April 12, 2026)
- ✅ Pi-hole gravity imported from x-server — 621k domains, 67 whitelisted, 40 blacklisted (April 12, 2026)
- ✅ Router DHCP DNS set to 192.168.1.11 — all devices query n-server Pi-hole (April 12, 2026)
- ✅ rsyslog remote receiver — receives and stores x-server logs on TCP 514 for forensic backup (April 14, 2026)
- ✅ Pi-hole updated — v6.4.2 Core, v6.6.1 FTL (April 30, 2026)
- ✅ Pi-hole HTTPS disabled — web UI on port 80 only, port 443 not in use (April 30, 2026)
- ✅ gitea system user hardened — shell changed to /usr/sbin/nologin (April 30, 2026)
- 🗑️ act_runner removed — was running as orphan process with no persistence, binary deleted (April 30, 2026)
- ✅ Home directory organized — scripts/, backups/ directories created (April 30, 2026)
- ✅ n-server-audit.sh added to ~/scripts/ — full system audit script (April 30, 2026)
- ✅ systemd-resolved disabled and masked — prevents port 53 conflict with Pi-hole on FTL restart (April 30, 2026)
- ✅ act_runner reinstalled properly — `act-runner.service` (host mode, v0.2.11), auto-deploys the HomeLab repo on push to main via `.gitea/workflows/`; supersedes the April 30 removal (May 25, 2026)
- 📋 WireGuard VPN — planned (future)

---

## 🔑 KEY LEARNINGS

- Ubuntu 24.04 uses socket-based SSH by default — `ssh.socket` overrides sshd_config port changes, must disable it first
- Mask `ssh.socket` (not just disable) — `systemctl mask ssh.socket` prevents Ubuntu from re-enabling it on reboot
- If SSH fails after reboot, try port 22 — if it hangs, the server is online but SSH isn't running; if refused on 2222, same story
- Samba needs both port 445 (SMB) and port 139 (NetBIOS) open in UFW
- Gitea WebAuthn warning on HTTP is harmless — just use username/password login
- Gitea over HTTP: use a personal access token (not your password) for git push
- `vbetool dpms off` hangs in systemd services — use `intel_backlight` via `/sys/class/backlight/` instead
- logind handles power button by default (shuts down) — set `HandlePowerKey=ignore` so acpid can take over
- Lid open is the emergency escape hatch — don't run any script on lid open, so the screen comes on naturally if SSH is unavailable
- UFW `delete allow <port>` won't work for rules with source restrictions — use `ufw delete allow from <subnet> to any port <port> proto <proto>` instead
- Syria blocks GitHub CDN — Pi-hole installer and blocklist updates need Cloudflare WARP to reach GitHub-hosted lists
- Cloudflare WARP grabs port 53 — conflicts with Pi-hole. Always `warp-cli disconnect` and `systemctl stop warp-svc` after use
- WARP reroutes all traffic including SSH — can drop active sessions. Always use `tmux` for long operations while WARP is active
- Pi-hole v6 uses its own built-in web server (no lighttpd) — web UI is on port 80 by default
- Pi-hole v6 enables HTTPS (port 443) by default with a self-signed cert — disable with `pihole-FTL --config webserver.port 80`
- Pi-hole v6 uses `pihole-FTL --config` for settings — env vars and `setupVars.conf` from v5 are ignored
- Pi-hole update command is `pihole -up` — `pihole update` does not exist in v6
- Pi-hole update needs WARP (GitHub blocked) — stop pihole-FTL first, then WARP up, update, WARP down, pihole-FTL up
- Pi-hole gravity DB can be copied between installs (Docker → bare metal) — blocklists, whitelist, and blacklist all transfer
- Individual blacklisted domains stored in the adlist table (instead of domainlist) cause harmless "invalid protocol" errors during `pihole -g` — clean with `DELETE FROM adlist WHERE address NOT LIKE 'http%'`
- Pi-hole installer picks the first available interface — if WARP is active, it binds to WARP's `172.16.0.x` instead of your LAN IP. Reconfigure interface after install
- rsyslog forwarding config (`10-forward-to-nserver.conf`) must only exist on the sender (x-server) — creating it on both sides causes an infinite syslog loop that bloats disk rapidly
- rsyslog `imtcp` module loading in `/etc/rsyslog.d/` works even though the default `/etc/rsyslog.conf` has it commented out — no need to edit the main config
- The rsyslog `stop` directive is critical — without it, remote logs also get written to n-server's own syslog, mixing the two servers' messages
- Remote log files are owned by `syslog:adm` — use `sudo` to read them
- To add more servers to remote logging, the template already handles it — logs go to `/var/log/remote/%HOSTNAME%/` automatically, just add a new `if $fromhost-ip ==` block or remove the IP filter
- System user accounts (gitea, etc.) should have shell set to `/usr/sbin/nologin` — use `sudo usermod -s /usr/sbin/nologin <user>`
- Gitea Actions runner (`act_runner`) has no persistence by default if installed manually — won't survive a reboot unless added as a systemd service (now done — `act-runner.service`)
- act_runner runs in **host mode** here (no Docker) — every label must be `<name>:host`; a `:docker` label makes it try Docker and fail. No `node` on the box either, so workflows must avoid JS actions (no `actions/checkout`) and use plain `git` in `run:` steps
- act_runner `config.yaml` schema drifts between 0.2.x minors — generate it with `act_runner generate-config` from the exact pinned binary so the schema always matches, and pin the version to the Gitea release era (0.2.11 ↔ Gitea 1.23.5)
- Gitea 1.23.5 has **no workflow-dispatch API endpoint** — `.../actions/workflows/<file>/dispatches` 404s (it landed in a later Gitea), and `.../actions/workflows` (list) also 404s. Trigger a manual run from the web UI, or push a commit matching the path filter. A PAT only authenticates `/api/` routes, not the HTML pages; poll runs at `GET /api/v1/repos/<owner>/<repo>/actions/tasks`
- The bare `act_runner daemon` ExecStart ignores `~/config.yaml` unless you pass `-c` — without it the runner falls back to built-in defaults (Docker labels) and breaks on this no-Docker box
- `systemd-resolved` will grab port 53 if Pi-hole FTL is ever down even briefly — FTL restarts fail with "Address in use". Fix: `sudo systemctl stop systemd-resolved && sudo systemctl restart pihole-FTL`. Permanently prevent with `sudo systemctl disable systemd-resolved && sudo systemctl mask systemd-resolved`
