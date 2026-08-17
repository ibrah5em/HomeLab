# the operator's Home Lab — Claude Code Project

This project gives Claude full context about my two-server home lab, local system, and tooling.
All commands assume you are running from my WSL2 environment (`homelab` on Ubuntu 24.04 in WSL2).

---

## ⛔ THE LAB IS RETIRED — read this before acting on anything below

**As of 2026-08-17 both servers are decommissioned and awaiting a disk wipe.** Everything in
this file about running services, deploys, nginx, SSL, VPN and monitoring is a **historical
record**, not a live system. Full story: `docs/decommission-2026-08.md`.

**What this means in practice:**

- **Don't propose deploys.** `configs/x-server/deploy.sh`, `configs/n-server/deploy.sh`, the
  Gitea Actions runner and the `.gitea/workflows/` chain all target machines that are going away.
  The `new-service` and `deploy` skills assume x-server and no longer apply.
- **The "push to `main` = arbitrary sudo on both servers" trust model is moot** — but keep the
  branch-then-merge discipline anyway; it's good practice and the repo still holds real history.
- **`ssh x-server` / `ssh n-server` may still work** until the boxes are wiped. Treat anything
  you find there as already archived — don't rely on it, and don't change it.
- **Sites live on Cloudflare now**, not x-server: `example.com`, `nemo-curly`, `kids-app-kids`.
  The `~/HomeLab` docs are not the place to manage them.
- **Salvage is at `<archive>/`** (98 MB, has its own `README.md`). If you need a
  config, a script, an nginx.conf or the old logs, read them there — not off the servers.

**Still true and still load-bearing:**

- This repo is **Gitea-only, never GitHub** — see the hard rule below. That doesn't change when
  Gitea goes; the copy of record becomes `~/HomeLab` plus the bare mirror in the archive.
- The git-history rules below (never force, never rewrite, fix with a new commit) still stand.
- `~/.server-creds.env` still holds the sudo passwords and `GITEA_PASSWORD` while the boxes are up.

---

## 📦 HomeLab Repo Rules — READ FIRST

`~/HomeLab/` is a **private Gitea repository** at `http://192.168.1.11:3000/homelab/homelab`.
It is on n-server, LAN-only, dark to WAN. Token in `~/.config/git-token` (chmod 600).
Credentials cached in `~/.git-credentials` — `git push` from `~/HomeLab` is silent and Gitea-bound.

### 🚫 Hard rule: this repo is NEVER on GitHub or any public site
- `git push` from `~/HomeLab` goes to Gitea on n-server. Period.
- Do **not** suggest `gh` CLI, GitHub Actions, GitHub Pages, github.com URLs, or public-PR workflows for this repo.
- Do **not** apply "careful, this is going public" caution heuristics — it's a LAN box owned by the operator.
- Do **not** propose changing the remote to GitHub or mirroring it there.
- The remote is `http://192.168.1.11:3000/homelab/homelab.git` and stays that way.

### 🚫 Hard rule: new top-level folders need approval before push
If a brand-new top-level folder appears in `~/HomeLab/` that isn't matched by `.gitignore`:
1. **Stop before staging it.** Don't `git add .` blindly.
2. Show the operator the folder name + a one-line summary of contents.
3. Ask: "push this to the homelab repo, gitignore it, or leave it untracked for now?"
4. Only proceed after explicit confirmation.

This catches accidental drops (project copies, backup dumps, scratch dirs) before they hit the repo.
**Adding files inside an already-tracked folder doesn't trigger this** — only new top-level dirs.

### 🚫 Hard rule: history is sacred — never rewrite, never force
The repo's git log is the project's memory. Do **not**:
- `git push --force` or `git push -f` — ever. Not even `--force-with-lease`.
- `git reset --hard` on any commit that has been pushed.
- `git rebase` a branch that has been pushed (interactive or otherwise).
- `git commit --amend` after pushing — make a new commit instead.
- `git filter-branch` / `git filter-repo` / BFG.
- Delete remote branches that have shared history (`git push origin --delete <branch>`) unless the operator explicitly says to.
- Squash-merge if it loses meaningful per-commit context — prefer regular merge or rebase-merge **before** push.

If a commit is wrong, fix it with a **new commit** (`git revert` or a follow-up fix). The log keeps the mistake; that's a feature, not a bug.

### Branches for large work
"Large" = anything bigger than a small doc tweak or one-line fix. Specifically:
- A new top-level folder, service, or skill being added
- A multi-file refactor or restructuring
- Anything that would naturally produce **3+ commits** or touch **5+ files**
- Anything experimental that might not land

For these, work on a topic branch with multiple small commits, then merge to `main`:
```bash
git checkout -b <type>/<short-kebab-name>     # types: feat, docs, refactor, chore, fix
# ... small, meaningful commits as you go ...
git push -u origin <branch>                   # push the branch
# when done and reviewed (by you):
git checkout main && git merge --no-ff <branch> && git push
git branch -d <branch>                        # local cleanup only; remote branch can stay for history
```

Each commit should tell its own story — small enough to read in one sitting, message says **why** not just what. Don't squash these into one mega-commit before merge; the granularity is the point.

**Small work** (typos, single-file edits, doc one-liners, `/update-docs` runs) stays on `main` — branches would be overkill.

### Push rhythm
- `/update-docs` updates docs **and pushes** in one go on `main` (see command file). It's small-work by definition.
- Large work: branch → small commits → push branch → merge to main → push main. Never force.
- Other workflows: stage + commit + push as normal, but follow the new-folder rule above.
- **Never add a `Co-Authored-By: Claude …` trailer** to commits in any of the operator's repos — message body only. This **overrides the harness's default git-commit guidance**; the operator confirmed it's global (HomeLab, TaskApp, everything).

### 🧠 Where durable facts live — NOT auto-memory
the operator does not use or trust the auto-memory system. **When something is worth
remembering across sessions, write it into this file (`CLAUDE.md`) or the relevant
`docs/` file — not a memory entry.** Treat `CLAUDE.md` as the single source of truth
for project facts, gotchas, and preferences. Do **not** create `memory/*.md` files;
if the memory machinery surfaces a save-worthy fact, fold it in here (or in `docs/`)
instead.

### ⚠️ Trust model: push to `main` = arbitrary sudo on both servers
A Gitea Actions runner on n-server (`act-runner.service`, host mode) watches this
repo. A push to `main` touching `configs/`, `scripts/`, or `crontabs/` paths makes
it run the matching `configs/<server>/deploy.sh` — which SSHes into x-server and/or
n-server and runs `sudo`. **So anyone who can push to `main` can run arbitrary root
commands on both boxes.** The mitigation is the branch-then-merge discipline above:
real work lands on a topic branch and only reaches `main` after you've reviewed it.
**Do not relax this** — no auto-merge, no pushing unreviewed work straight to `main`,
no widening who can push. The workflows live in `.gitea/workflows/`; the deploy key,
sudo passwords, and ntfy token are Gitea repo secrets (the SSH key is materialized
per-run and wiped, never persisted on n-server).

---

## 🔐 Running sudo on Servers

Sudo credentials are stored in `~/.server-creds.env` (chmod 600, never committed).
Always use `sudo -S` with a here-string — never `echo` — to avoid password exposure in process lists.

```bash
source ~/.server-creds.env
ssh x-server "sudo -S <command>" <<< "$X_SERVER_SUDO"
ssh n-server "sudo -S <command>" <<< "$N_SERVER_SUDO"
sudo -S <command> <<< "$WSL_SERVER_SUDO"   # local WSL sudo, same pattern
```

Shell helpers available after `source ~/tools/zsh/.zshrc`:
```bash
xsudo <command>   # sudo on x-server
nsudo <command>   # sudo on n-server
```

> NOPASSWD sudoers entries are intentionally avoided — sudo must stay password-gated on the public-facing server to prevent privilege escalation if a container or service is ever compromised.

### Gitea account password — `GITEA_PASSWORD`

`~/.server-creds.env` also carries `GITEA_PASSWORD`: the web-UI / HTTP-push password for the
`homelab` Gitea account (rotated 2026-08-05 — the previous one was weak and had leaked
into a repo's history). This is **separate** from `~/.config/git-token`, which is the
API token used for the HomeLab repo itself.

Most repos won't need it — `~/.git-credentials` caches the Gitea entry, so pushes are
silent. When a push does need credentials unattended (fresh clone, post-rotation), pass
it through a transient helper so it never reaches a command line, a config file, or the
process list:

```bash
source ~/.server-creds.env; export GITEA_PASSWORD
git -c credential.helper='!f(){ test "$1" = get && \
  printf "username=homelab\npassword=%s\n" "$GITEA_PASSWORD"; };f' push origin <branch>
```

Because `credential.helper=store` is set globally, a successful push writes the password
into `~/.git-credentials` (plaintext, 0600) — that's intended, it's what keeps later
pushes silent. **Re-run that helper after any rotation**, otherwise the stale cached
entry 401s.

---

## 🗺️ Network Topology

```
Internet (<WAN-IP>)
    │
    ├── site.example.net  →  x-server (nginx, port 80/443)
    │
Router: <router-model> (192.168.1.1)
    │
    ├── x-server  192.168.1.10  (HP G62, i3 M330, 6GB RAM, Ubuntu 24.04)
    │       └── WireGuard VPN: 10.0.0.1  (wg0, port 51820)
    │
    └── n-server  192.168.1.11  (HP laptop, i3-2370M, 4GB RAM, Ubuntu 24.04)
```

**My dev machine:** WSL2 Ubuntu 24.04 on Windows 11, hostname `dev-box`

---

## 🖥️ X-SERVER (192.168.1.10)

**Role:** Public-facing home server — nginx reverse proxy, Docker services, WireGuard VPN.

### SSH
```bash
ssh x-server          # uses ~/.ssh/config → Port 2222, key ~/.ssh/x-server-new
```
Config: `HostName 192.168.1.10 | Port 2222 | User homelab | IdentityFile ~/.ssh/x-server-new`

### Running Services (Docker unless noted)

| Service | Container / Type | Domain / Port | Notes |
|---|---|---|---|
| **nginx** | Docker (`nginx-ssl`) | :80/:443 public | Reverse proxy + SSL termination |
| **KidsApp** | Docker (`kids-app`) | kids.example.net | Arabic children's ed platform (Node.js). Image `kids-app:latest` built **on x-server** by GH Actions self-hosted runner (repo `<partner-account>/<kids-app>`) on push to `main`. Source rsynced to `~/docker/kids-app/app/` (not GHCR, not Watchtower). |
| **TaskApp** | Docker (`tasks`) | tasks.example.net | Simple Task Manager (Laravel + SQLite). Image `ghcr.io/<user>/tasks:latest`, built by GH Actions on push to `main`, rolled by Watchtower. Deploy dir `~/docker/tasks/` holds only compose + .env. |
| **Portfolio** | Docker (`portfolio`) | site.example.net **only** — `example.com` left x-server 2026-08-08 (see Cloudflare note below) | Static portfolio (nginx:alpine + index.html/img). Image `ghcr.io/<user>/portfolio:latest`, built by GH Actions on push to `main` (repo `homelab/portfolio`), rolled by Watchtower. Deploy dir `~/docker/portfolio/` holds only compose, proxied at `172.18.0.92`. **Now a warm standby**: the duckdns vhost still serves it and the GHCR→Watchtower pipeline still rolls it, but the live site is on Cloudflare. Kept as the rollback path — don't decommission until the role swap is settled. |
| **ntfy** | Docker (`ntfy`) | ntfy.example.net (WAN) / :8083 (LAN) | Push notifications |
| **Watchtower** | Docker (`watchtower`) | — | Label-scoped image roller; polls GHCR every 60s for opted-in containers (`tasks`, `portfolio`). Compose at `~/docker/watchtower/`. |
| **WireGuard** | Native (host) | 10.0.0.1, port 51820/udp | VPN server |
| **Samba** | Native (`smbd`, `nmbd`) | 445/139, LAN + VPN only | Single share: `files` → `/mnt/storage/files` (read/write). `home` share was dropped 2026-05-24 — exposed `~/.ssh/`, `~/.server-creds.env`, `~/.git-credentials`, every `~/docker/**/.env`. SSH for config edits instead. `hosts allow = 192.168.1.0/24 10.0.0.0/24 127.0.0.1`, `map to guest = never`. |
| **GH Actions runner** | systemd (`actions.runner.<partner-account>-kids-app-kids.x-server.service`) | — | Self-hosted GitHub Actions runner; only deploys kids-app (`<partner-account>/<kids-app>` repo). Runs as `homelab`, binary in `~/actions-runner/`. |
| **server-cmd.py** | systemd (`server-cmd.service`) | ntfy topics | ChatOps daemon |
| **nginx-watcher** | systemd (`nginx-watcher.service`) | — | Breach detector — pushes only when an exploit path returns 2xx (ships in SHADOW mode) |
| **login-watcher** | systemd (`login-watcher.service`) | — | Alerts on external-source SSH logins + unexpected sudo (journald follower) |
| **AIDE** | systemd timer | — | File integrity monitoring |
| **backup.sh** | cron (root) | — | Weekly backup, Tue 2 AM |

### Key Paths
```
Docker Compose files:  ~/docker/docker-compose.yml
nginx config:          ~/docker/nginx.conf          (monolithic, all vhosts in one file)
nginx banned-ips:      ~/docker/banned-ips.conf     (included in every server block)
nginx logs:            ~/docker/nginx-logs/
certbot certs:         ~/docker/certbot/conf/live/
ntfy config:           ~/docker/ntfy/etc/server.yml
ntfy env:              ~/docker/ntfy/.env
WireGuard config:      /etc/wireguard/wg0.conf
WireGuard peers:       /etc/wireguard/peers/
backup script:         ~/scripts/backup.sh
server-cmd script:     ~/scripts/server-cmd.py
GH Actions runner:     ~/actions-runner/   (deploys kids-app from <partner-account>/<kids-app>)
AIDE config:           /etc/aide/aide.conf.d/99_x-server
Samba config:          /etc/samba/smb.conf
UFW rules:             /etc/ufw/before.rules (has Docker NAT + WireGuard FORWARD)
Docker daemon:         /etc/docker/daemon.json  (iptables: false)
x-server docs:         ~/HomeLab/docs/x-server-docs.md       (source of truth, on WSL)
x-server configs:      ~/HomeLab/configs/x-server/docker/    (authored copies; deploy via configs/x-server/deploy.sh)
x-server scripts:      ~/HomeLab/scripts/x-server/           (authored copies of ~/scripts/; same deploy.sh pushes them)
```

### Docker Network
```
docker_management  →  bridge  br-management  172.18.0.0/16
  - nginx-ssl:        172.18.0.100 (pinned)
  - kids-app:            172.18.0.90  (pinned)
  - tasks:               172.18.0.91  (pinned)
  - portfolio:172.18.0.92  (pinned)
  - ntfy:              172.18.0.83  (pinned)
  - watchtower:       ephemeral    (needs docker_management for ghcr.io egress)
  - certbot:          ephemeral (uses --network docker_management)
```
**Critical:** `iptables: false` in daemon.json — NAT/FORWARD rules live in `/etc/ufw/before.rules`, NOT iptables directly.
**Critical:** `docker compose exec nginx nginx -s reload` for zero-downtime nginx reloads (not restart).

### Firewall Summary
| Port | Service | Access |
|---|---|---|
| 80/443 | nginx | 🌍 Public |
| 51820/udp | WireGuard | 🌍 Public |
| 2222/tcp | SSH | 🏠 LAN + VPN only |
| 8083/tcp | ntfy | 🏠 LAN + VPN only |
| 445/tcp, 139/tcp, 137/138/udp | Samba | 🏠 LAN + VPN only |

### SSL / Domains
All Let's Encrypt, all renew Sunday 3 AM via cron.
- ~~`example.com` + `www.example.com`~~ — **no longer served by x-server as of 2026-08-08.** Moved to Cloudflare Workers (Static Assets); DNS moved Namecheap → Cloudflare nameservers. See "Portfolio on Cloudflare" below. **Drop both names from the certbot renewal list** — HTTP-01 webroot can't succeed now that DNS points at Cloudflare, and the stale cert (expires 2026-08-21) will fail the Sunday renew and fire a false SSL-failure alert.
- `site.example.net` — still on x-server, still proxies to the `portfolio` container. Now the *rollback* path rather than the fallback-for-lapsed-registration. Still carries `Link: rel=canonical` → `example.com` and `X-Robots-Tag: noindex`, which stays correct: the canonical target is just served by Cloudflare instead.
- `kids.example.net` — KidsApp platform
- `tasks.example.net` — Simple Task Manager (Laravel)
- `ntfy.example.net` — ntfy push (WebSocket-upgraded reverse proxy to the local ntfy container)
- Certbot: `docker run --rm --network docker_management certbot/certbot ...`
- Check: `sudo docker compose exec nginx nginx -t` before any reload

### 🌩️ Portfolio on Cloudflare — `example.com` (moved off x-server 2026-08-08)

**Why:** the solar system cuts power every 1–4 days and x-server takes the hit every time.
The portfolio is the one thing with an outside audience, so it moved to hosting that
doesn't depend on the house having power. Proven the same day — x-server was powered off
and the site stayed up.

**Where it lives now:** Cloudflare **Workers with Static Assets** (Pages went into
maintenance mode April 2025, so the Git integration builds Workers now). Chosen over
GitHub Pages because it serves a **private** repo without depending on Student Pack Pro
staying active, and has no bandwidth cap.

- **Repo:** `~/projects/portfolio` (GitHub — this one is *not* Gitea).
- `scripts/build-static.sh` + `_headers` (commit `444c5e2`) — the build exists so the repo
  root isn't the publish root; `docker-compose.prod.yml` carries x-server's internal Docker
  IPs and had no business being public.
- `wrangler.jsonc` (commit `ac3c37e`) — assets-only, no `main` entrypoint.
- Build command `bash scripts/build-static.sh`, output `dist`.
- **DNS:** moved Namecheap → Cloudflare nameservers. Delegation flipped in ~10 min. All five
  MX records and the TXT survived the move (that TXT is the Search Console verification).
- **Apex** `example.com` is a Worker **Custom Domain**. **`www`** wouldn't accept a Custom
  Domain attach, so it's a proxied CNAME → apex plus a wildcard **Redirect Rule** (real 301,
  path + query preserved, matching what nginx did). "Always Use HTTPS" is on.

**Cloudflare gotchas — all three cost real time:**
- **Attaching a Custom Domain fails while any A/CNAME exists for that hostname.** The record
  must be deleted first, which briefly takes the hostname dark — so delete and attach back to back.
- **Stale resolvers will lie to you.** Testing from WSL twice reported `server: nginx` and
  `www` still pointing at x-server, both from cached answers, long after the cutover was live.
  Pin it: `curl --resolve <host>:443:<cloudflare-ip>`.
- **A freshly saved Redirect Rule can 522 on individual PoPs** for a minute or so. One PDF
  path failed once, then passed nine straight retries. Don't debug it immediately — retry first.

**Loose ends (none urgent):** Namecheap's free email forwarding died with the nameserver move
(it only works on Namecheap NS) — nothing depended on it, the CV uses Gmail; Cloudflare Email
Routing is there if `@example.com` is ever wanted. x-server still has the `.me` nginx vhost and
GH Actions still pushes to GHCR on every commit — both harmless, and deliberately left until
the role swap is settled.

---

## 🖥️ N-SERVER (192.168.1.11)

**Role:** LAN utility box — DNS, file sharing, Git hosting, log storage. 100% dark to WAN.

### SSH
```bash
ssh n-server          # uses ~/.ssh/config → Port 2222, key ~/.ssh/n-server
```
Config: `HostName 192.168.1.11 | Port 2222 | User homelab | IdentityFile ~/.ssh/n-server`

### Running Services (all bare metal, no Docker)

| Service | Port | Access | Notes |
|---|---|---|---|
| **Pi-hole** | 53 (DNS), 80 (web) | 🏠 LAN | v6.x, gravity: 621k domains |
| **Gitea** | 3000 | 🏠 LAN | SQLite, binary at `/usr/local/bin/gitea` |
| **Samba** | 445, 139 | 🏠 LAN | Shares `/home/homelab/Downloads` as `n-server-home` (path is Downloads, not the home dir) |
| **rsyslog receiver** | 514/tcp | 🏠 LAN | Receives x-server logs |
| **pyLoad** | 8000 | 🏠 LAN + VPN | `pyload-ng` download manager (direct/file-hoster, **not** torrents). pipx install, systemd `pyload.service`, web UI bound `0.0.0.0:8000`, ufw-scoped to `192.168.1.0/24` (VPN reaches it via x-server masquerade). Downloads → `~/Downloads` = the Samba share. Default `pyload/pyload` login removed; user `admin` + strong pw (hash in `~/.pyload/data/pyload.db`). |

### Key Paths
```
Pi-hole config:        /etc/pihole/pihole.toml
Pi-hole gravity DB:    /etc/pihole/gravity.db
Gitea config:          /etc/gitea/app.ini
Gitea data:            /var/lib/gitea/
Samba config:          /etc/samba/smb.conf
pyLoad config:         ~/.pyload/settings/pyload.cfg  (+ user DB ~/.pyload/data/pyload.db)
pyLoad systemd unit:   /etc/systemd/system/pyload.service
rsyslog receiver:      /etc/rsyslog.d/10-receive-x-server.conf
x-server remote logs:  /var/log/remote/x-server/
Scripts:               ~/scripts/
Backups:               ~/backups/
n-server docs:         ~/HomeLab/docs/n-server-docs.md  (source of truth, on WSL)
```

### Access URLs
```
Pi-hole UI:   http://192.168.1.11/admin
Gitea:        http://192.168.1.11:3000
Samba:        \\192.168.1.11\n-server-home
pyLoad:       http://192.168.1.11:8000   (LAN or via WireGuard VPN)
```

### Critical Notes
- `systemd-resolved` is **disabled and masked** — prevents port 53 conflict with Pi-hole
- Cloudflare WARP installed for on-demand GitHub CDN bypass (Syria blocks it)
  - Always disconnect WARP after use: `warp-cli disconnect && sudo systemctl stop warp-svc`
  - WARP grabs port 53 — conflicts with Pi-hole
- Pi-hole v6 uses `pihole-FTL --config` for settings (not env vars)
- Pi-hole update: `pihole -up` (needs WARP active, stop pihole-FTL first)

---

## 💻 MY SYSTEM (WSL2)

**OS:** Ubuntu 24.04.3 LTS in WSL2 (Windows 11, i5-13450HX, ~7.8GB RAM)
**Shell:** zsh + Powerlevel10k + Oh-My-Zsh
**ZDOTDIR:** `~/tools/zsh/` (set via `~/.zshenv`)
**System docs:** `~/HomeLab/docs/system-docs.md` (source of truth)

### Key Aliases & Tools
```bash
# Python
python / py     → python3
pip             → pip3
venv-create     → python3 -m venv venv
activate        → source venv/bin/activate

# Project shortcuts
proj            → cd ~/projects
projects        → cd ~/projects && ls -la
```

### Scripts (`~/scripts` — all on PATH)
```
tool                    # Interactive menu launcher for all scripts
tool git-helper         # Git dashboard
tool health-check       # System health report
tool sysmon             # System snapshot
tool docker-cleanup     # Docker cleanup
tool update-all         # Update apt/pip/Docker/Ollama
tool deploy             # Deploy project to x-server
tool ssl-check          # Check SSL certs for my domains
tool ip-lookup <ip>     # IP intelligence
tool system-backup      # Backup WSL to /mnt/c/Backups/WSL_Backups/
```

### Node.js / Python
- NVM for Node.js, `uv` for Python packages (`~/.local/bin/uv`)
- Global npm path: `~/.npm-global/bin`
- Global npm packages: `sass`, `yarn`

### Ollama + Open WebUI
```bash
ollama serve &                    # Start Ollama (manual, auto-start disabled)
docker start open-webui           # Start Open WebUI on :3000
~/scripts/system-scripts/startup.sh  # Start both
```

---

## 🔑 Key Gotchas (Burned Before)

- **Docker iptables: false** → NAT/FORWARD rules MUST be in `/etc/ufw/before.rules`, NOT iptables CLI
- **nginx reload** → always use `docker compose exec nginx nginx -s reload`, never restart
- **nginx config test** → `docker compose exec nginx nginx -t` (not `docker run --rm`)
- **Certbot** → must use `--network docker_management`, not default bridge
- **Docker volume names** → Compose prefixes with project name: `docker_kids-app-data` not `kids-app-data`
- **DNAT rules** → flush stale rules first: `sudo iptables -t nat -F PREROUTING` before `ufw reload`
- **Groq API blocked** → proxied through a Cloudflare Worker from KidsApp app
- **GitHub CDN blocked** → use Cloudflare WARP on n-server for Pi-hole/Gitea updates
- **Syria blocks** → font CDNs, Groq API, Telegram, many GitHub CDN domains
- **WARP port 53 conflict** → always `warp-cli disconnect` after use on n-server
- **Samba** → has its own password store; `smbpasswd -a user` then `smbpasswd -e user`
- **`node:18-alpine`** → has built-in `node` user (UID 1000); just `USER node` in Dockerfile
- **CSP + nginx** → let the app handle CSP via Helmet; adding in nginx = duplicate headers
- **`docker compose restart`** → does NOT pick up new volume mounts; use `up -d`
- **BuildKit** → disabled (`DOCKER_BUILDKIT=0`) on x-server — silent npm ci bug
- **WireGuard** → native on host, not Docker; masquerade + FORWARD rules in `before.rules`
- **rsyslog forwarding** → config only on sender (x-server); both sides = infinite loop
- **Pi-hole dnsmasq** → must set `dns.listeningMode=all` when using DNAT
- **`systemd-resolved`** → masked on n-server; if Pi-hole FTL ever goes down, resolved grabs :53
- **Watchtower + Docker 29** → daemon min API is 1.44; Watchtower's bundled SDK negotiates 1.25. Pin via `DOCKER_API_VERSION=1.44` env on the container.
- **Watchtower egress** → put it on `docker_management`, not default bridge — `iptables: false` means default bridge can't reach ghcr.io for HEAD requests (fallback pull works but logs warnings).
- **Two CI/CD patterns coexist on x-server** → TaskApp uses GH Actions (hosted runner) → GHCR → Watchtower polls and rolls. KidsApp uses a **self-hosted GH Actions runner on x-server** (different GitHub account, `<partner-account>/<kids-app>`) that rsyncs source, builds the image locally as `kids-app:latest`, and `docker compose up -d`s it. Don't assume "Docker service on x-server" means GHCR/Watchtower — check whether the image tag has a registry prefix.
- **ProtonVPN (free) on Windows kills LAN access — unfixable on its free tier** → if Windows can't ping 192.168.1.x (router/x/n) but WSL can, ProtonVPN is dropping LAN packets below the routing layer. WSL traffic rides Hyper-V's vSwitch (`172.24.32.x`) and bypasses the filter, which is why `scp`/`ssh` from the WSL terminal work fine while Windows-side SMB drag-drop crawls or fails. Symptom: "General failure" on `ping 192.168.1.1` from Windows, or mapped-drive ISO transfers limping at 1–2 MB/s.
  - **Root cause (confirmed 2026-05-26):** ProtonVPN free uses **WireGuard** with `AllowedIPs = 0.0.0.0/0`. WireGuard's driver then auto-installs a WFP filter that **blocks all untunneled traffic** — this is WireGuard's *built-in* kill switch, separate from ProtonVPN's UI kill-switch toggle. Turning off ProtonVPN's own kill switch does NOT remove it.
  - **What does NOT work:** static LAN route (`route add 192.168.1.0 mask 255.255.255.0 ... -p`) — even a textbook on-link route loses, because WFP drops the packet at send time *below* routing. The paid "Allow LAN connections" toggle would fix it but is Plus-only.
  - **What works:** (1) switched to **Windscribe** instead — its split-tunnel / LAN handling lets `192.168.1.x` through on the free tier (this is the adopted fix). (2) Failing that: do all server admin from **WSL** (bypasses the filter entirely), or just disconnect the VPN for the few minutes you touch the servers.
- **Docker named-volume perms** → a fresh/recreated named volume's `_data/` is `root:root`; a non-root container (e.g. `node` at UID 1000) can read but not *write* → silent `EACCES` on SQLite saves, log rotation, temp-and-rename. Before first start: `sudo chown -R <UID>:<GID> /var/lib/docker/volumes/<vol>/_data/` (1000:1000 for `node:18-alpine`). KidsApp's `saveDB()` hit this. Bake into new-service onboarding alongside the pinned-IP step.
- **AIDE** → custom rules are `/etc/aide/aide.conf.d/99_x-server` (security paths only — no churn). Runs via **cron at 03:30** (not a systemd timer; the system `dailyaidecheck.service` ~03:41 is separate, its mail warning is ignorable). **`configs/x-server/deploy.sh` now auto-re-baselines AIDE** at the end of any run that wrote to a monitored path (`~/scripts`, systemd units, `before.rules`, root crontab) — the diff is pure mtime/ctime drift from scp/chmod, so the deploy absorbs it instead of leaving a "files changed" alert that re-fires nightly forever. **Manual re-baseline is only needed for monitored changes made _outside_ deploy.sh** (a hand-edit on the server), or if the auto step warns it was skipped/failed: `sudo aide --update --config /etc/aide/aide.conf && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db && sudo chown _aide:_aide /var/lib/aide/aide.db` (urgent to verify if `/var/spool/cron`, sudoers, ssh, or pam.d changed). The DB is owned by `_aide:_aide` — restore that after a root-run update or the `_aide`-run `dailyaidecheck.service` can't read it.
- **Gitea 1.23.5 has no workflow-dispatch API** → `.../actions/workflows/<f>/dispatches` 404s. To trigger a deploy, push a commit matching the path filter (or use the web UI). Runner is `act_runner` v0.2.11, **host mode**, label `ubuntu-latest:host` only (a `:docker` label breaks it).
- **nginx-watcher + SPA vhosts (false-positive class)** → the breach detector fires when a `NEVER_LEGIT` path returns 2xx, but a single-page app behind nginx returns `200` + its `index.html` for *every* unknown path — so an exploit probe (e.g. `/phpinfo`) against an SPA vhost trips a false "Exploit path returned 200" alert (the body is just the SPA, not a real leak). Hit 2026-06-16 via the **ntfy web UI** (`ntfy.example.net/phpinfo` → 200, 2504-byte ntfy index, byte-identical to the site root). Fixed by adding `if ($bad_qs)/if ($bad_uri) { return 403; }` to the ntfy HTTPS block, matching the app vhosts, so exploit paths 403 before reaching ntfy. **Any new SPA/proxy vhost must carry the same `$bad_uri`/`$bad_qs` deny** or it re-introduces the false positive. To confirm a phpinfo-style breach is real vs. SPA-noise: check response size + `curl` the path — real phpinfo is tens of KB; an SPA index is small and identical to the site root.
- **auto-ban semantics + the deploy-wipe trap** → `ban-ip.sh auto-ban` (hourly XX:05) bans an IP only if it produced **>20 responses of status `403` or `444`** within the **last 5000 access-log lines**. It is deliberately blind to `404`/`429`/`499`/`200` and to low-volume or IP-rotating scanners — so "why wasn't X banned?" is almost always "its probes `404`'d, it stayed under 20, or it scrolled out of the 5000-line window." Bans are appended to the **server's** `~/docker/banned-ips.conf` (the living source of truth). **`deploy.sh` now `union`s the server's live bans with the repo copy before pushing** (a deploy can only ADD, never DROP — fixed 2026-06-16; before, every deploy silently reverted the list to the repo's last-committed copy, discarding weeks of auto-bans). The repo copy is a loose archive — refresh it occasionally with `scp x-server:~/docker/banned-ips.conf configs/x-server/docker/banned-ips.conf`. Caveat of union-merge: un-banning an IP that's still in the repo copy gets undone on the next deploy — remove it from both sides.
- **unattended-upgrades silently stalls on `OnlyOnACPower` (laptop-as-server trap)** → both HP servers run `unattended-upgrades`, but the default `Unattended-Upgrade::OnlyOnACPower "true"` aborts every run when the box thinks it's on battery. **x-server's old G62 misreports wall power as battery** (`/sys/class/power_supply/AC*/online` = 0 while the battery sits `fully-charged` at 100% with weeks of uptime) — so for weeks it applied **nothing** and drifted 88 security updates behind (openssl, curl, cups, kernel) with `reboot-required` never even set. n-server reads AC correctly (`online` = 1) so it stayed current. Tell-tale in `/var/log/unattended-upgrades/unattended-upgrades.log`: `WARNING System is on battery power, stopping`. **Fix (applied 2026-07-05, both servers):** `/etc/apt/apt.conf.d/99-homelab-nobattery` → `Unattended-Upgrade::OnlyOnACPower "false";` (stationary boxes on wall power; the battery reading is noise). **Also:** plain `apt upgrade` holds back kernel metapackages (the new `linux-image-<ver>` is a *new* package name) — use `apt full-upgrade`/`dist-upgrade` to pull the kernel, then reboot to activate it. The **`Patches` section in the daily summary** now surfaces this same-day.
- **A domain that leaves x-server must also leave the certbot renewal list** → certs renew Sunday 03:00 via HTTP-01 webroot, which needs the domain's DNS to still point at x-server. Move the DNS elsewhere (as `example.com` did on 2026-08-08 → Cloudflare) and the renewal starts failing — and the SSL-failure alert is one of the few that pushes to ntfy, so it becomes a recurring **false** alarm that trains you to ignore a real one. Drop the names from the certbot `-d` list at cutover time, not after the first alert. The existing cert can just expire in place; nothing serves it anymore.
- **Known non-issues — don't flag in `/status`** → `power-watchdog.service` is intentionally disabled; WireGuard peers with no recent handshake are the operator's idle phone/laptop; nginx-watcher no longer emits scan/attack alerts (breach-only by design — see Monitoring Surface).

---

## 📡 Monitoring Surface

Alerts use the **self-hosted `ntfy` container** — one instance, two doors: scripts
publish locally (`192.168.1.10:8083`, topic `security-alerts`), and the phone
subscribes over the WAN at `https://ntfy.example.net` (nginx-proxied,
WebSocket-upgraded). A locally-published message is pushed straight down that live
subscription, so alerts reach the phone on LAN **or** cellular; anything missed during
a disconnect backfills from the container's `cache.db` on reconnect. Locked down:
TLS + `auth-default-access: deny-all` + token auth both directions (anonymous
read/publish → 403; `*` user has no access to any topic). This is deliberately *not*
public ntfy.sh — alert contents (attacker IPs, service status) stay on our own infra.
Tokens at `~/.config/ntfy-token.env` on x-server (0600): `NTFY_TOKEN` (admin, used by the daemons/senders) and `NTFY_CMD_TOKEN` (ntfy user `cmdbtn`, **write-only to `server-cmd`** — backs the one-tap action buttons; least-privilege so a leaked notification can't read alerts). All cron-based alerters call `~/scripts/ntfy-send.sh`.

### ntfy Topics

| Topic | Direction | Senders |
|---|---|---|
| `security-alerts` | x-server → phone | nginx-watcher (breach), login-watcher, server-health, daily-summary, aide-check, SSL/backup failure, server-cmd replies |
| `server-cmd` | phone → x-server | `server-cmd.py` listener (ChatOps) |

### Alert Sources

| Source | Schedule | What it fires on |
|---|---|---|
| `nginx-watcher.service` | continuous tail | **Breach only**: an exploit path (wp-login, phpMyAdmin, `.env`/`.git`, LFI…) returning 2xx. Scans/attempts are *not* pushed — they go to the daily digest. Ships in SHADOW mode (logs `WOULD ALERT`, no push) until validated, then flip `SHADOW=False`. Carries a [Ban this IP] button |
| `login-watcher.service` | continuous (journald) | External-source SSH login (outside LAN+VPN), or sudo by a user other than homelab/root |
| `server-cmd.service` | continuous listen | Whitelisted ChatOps commands from phone; also backs the [Ban]/[Restart] action buttons (via write-only `NTFY_CMD_TOKEN`) |
| `dailyaidecheck.timer` | daily 03:30 UTC | File integrity diffs (mail to `_aide` mbox) |
| `aide-check.sh` (cron) | daily 03:30 UTC | Integrity changes, **path-listed + severity-graded**: urgent if sudoers/pam.d/ssh/ufw/wireguard/cron change, high otherwise (deploys). Re-baseline AIDE after deploys |
| SSL renew cron | Sun 03:00 UTC | Cert renewal **failure only** (success is silent; expiry days shown in daily summary) |
| `ban-ip.sh auto-ban` | hourly XX:05 | Repeat-offender bans (silent; count shown in daily summary) |
| `server-health.sh` | every 10 min | Container down (all 6 apps), disk full, **HTTP 5xx/timeout via nginx**; one-shot "recovered" when it clears. [Restart] button on container-down |
| `daily-summary.sh` | daily 08:00 UTC | The one routine touchpoint — **`low` priority** (no buzz). Security volume, top attackers, auto-bans, cert expiry, backup age, service restarts, **patch drift** (pending security updates + kernel currency, ⚠ on drift) |
| `backup.sh` (root cron) | weekly Tue 02:00 | Backup **failure only** (success is silent; age shown in daily summary) |

### Log Archive

x-server forwards syslog to n-server (rsyslog on 514/tcp, sender-side only — adding the same
rule on n-server creates an infinite loop). Archived at `/var/log/remote/x-server/<program>.log`
on n-server. Use this as the durable record; ntfy.sh has no retention guarantee.

---

## 📋 Common Workflows

### Add a new site to x-server
nginx is monolithic — all vhosts live in one `nginx.conf` file. The repo at
`~/HomeLab/configs/x-server/docker/nginx.conf` is the source of truth; edit there.
1. In `~/HomeLab/configs/x-server/docker/nginx.conf`, add an HTTP `server` block for the ACME challenge.
2. Deploy: `~/HomeLab/configs/x-server/deploy.sh` (scp + test + zero-downtime reload, with rollback on test failure).
3. Run certbot for the new domain (on x-server):
   `docker run --rm --network docker_management -v ~/docker/certbot/conf:/etc/letsencrypt -v ~/docker/certbot/www:/var/www/certbot certbot/certbot certonly --webroot -w /var/www/certbot -d <domain>`
4. Add the HTTPS `server` block in the repo, deploy again.
5. Update `docs/x-server-docs.md`.

### Deploy a Docker service
1. Create compose file in `~/docker/<service>/`
2. Create `.env` file for secrets (never hardcode)
3. `docker compose up -d`
4. Add nginx reverse proxy config
5. Pin container IP with `ipv4_address` in compose if DNAT rules depend on it

### Update Pi-hole on n-server
1. `ssh n-server`
2. `sudo systemctl stop pihole-FTL`
3. `sudo warp-cli connect` (wait for connection)
4. `pihole -up`
5. `sudo warp-cli disconnect && sudo systemctl stop warp-svc`
6. `sudo systemctl start pihole-FTL`

### Check WireGuard peers
```bash
ssh x-server "sudo wg show"
```

### Emergency: x-server won't wake (power outage)
- x-server has RTC wake configured — it should auto-resume from hibernate
- WoL doesn't work (NIC loses power on shutdown)
- Physical access required if RTC wake fails
