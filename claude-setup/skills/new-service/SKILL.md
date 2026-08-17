---
name: new-service
description: >
  Use this skill whenever the operator wants to onboard a new site or Docker service to x-server —
  any request like "add a new site", "deploy a new app on x-server", "set up <domain>",
  "add <name>.example.net", "spin up a new container behind nginx", or anything that
  needs the DuckDNS + docker-compose + nginx + Let's Encrypt + docs chain.
  Triggers on "new service", "new site", "new subdomain", "add a service",
  "onboard <X> to x-server".
---

# new-service — End-to-End Service Onboarding on x-server

This skill walks the full onboarding chain for a new service on x-server. The chain is brittle
in a specific order — DuckDNS first, then nginx HTTP-only block for ACME, then certbot, then
HTTPS block, then verify, then docs. Skipping the HTTP-only intermediate step is the #1
failure mode (certbot can't reach the ACME challenge through an HTTPS-only config that points
at a not-yet-running service).

## Step 1 — Gather Intent

Before touching anything, collect these inputs from the operator. Ask only for what's missing.

Required:
- **Service name** — kebab-case, used as compose project name, container name, and config filename
- **Subdomain** — full hostname (e.g. `app.example.net`) or path under `site.example.net` (e.g. `/myapp`)
- **Service type** — Docker container, static site (served by `nginx-ssl`), or path-mounted static folder
- **Upstream** — if Docker: container name + internal port. If static: filesystem path inside `nginx-ssl`
- **Pinned IP?** — if any DNAT/UFW rule depends on the container's IP, pin it under `172.18.0.0/16` in the compose file

Helpful but optional:
- WebSocket support needed?
- Body size limit higher than nginx default 1m?
- Any client-IP/header requirements?

If the answer is "I don't know" for upstream or pinned IP, default to: bridge container on
`docker_management`, no pinned IP, internal port discovered from the container's `EXPOSE`.

## Step 2 — DuckDNS Subdomain

Read `references/duckdns.md` for the exact procedure. Two sub-cases:

- **New subdomain** (`<name>.example.net`) — must be created in the DuckDNS web UI under
  the operator's account, then pointed at the current public IP `<WAN-IP>`. Verify with
  `dig +short <name>.example.net` from WSL before continuing.
- **Path under existing domain** (`site.example.net/<path>`) — no DNS change needed.

Do not proceed past Step 3 until DNS resolves to the expected IP.

## Step 3 — Docker Compose Service (if Docker)

Read `templates/docker-compose.yml` for the base service block. Place the new service:

- File: `~/docker/<service>/docker-compose.yml` (own compose project) OR
- Append to `~/docker/docker-compose.yml` (existing nginx-ssl project) if it must share the
  network without extra wiring. Default to **own compose project** unless the operator says otherwise.

Critical points the template enforces:
- `networks: [docker_management]` with `external: true`
- `container_name: <service>` matches the service name exactly
- `restart: unless-stopped`
- Env vars sourced from a sibling `.env` (use `templates/env-example` as the skeleton)
- Pinned IP only if the user asked for it (write the `ipv4_address` field)
- `DOCKER_BUILDKIT=0` if there's a build step — BuildKit is disabled on x-server and a
  silent `npm ci` bug bit us before

Build/start command:
```bash
ssh x-server "cd ~/docker/<service> && DOCKER_BUILDKIT=0 docker compose up -d"
```

## Step 4 — nginx HTTP-Only Block (ACME Challenge)

Read `templates/nginx-site.conf` and use the **HTTP-only** half first. Filename:
`~/docker/nginx/conf.d/<service>.conf`.

```bash
scp /tmp/<service>.conf x-server:~/docker/nginx/conf.d/<service>.conf
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -t \
  && docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload"
```

If `nginx -t` fails, fix the config and re-test. Never restart the container.

## Step 5 — certbot

Read `references/certbot.md` for the exact incantation. The non-obvious bits:

- Must run with `--network docker_management` so certbot can hit nginx-ssl on the shared network
- Volumes: `~/docker/certbot/conf` → `/etc/letsencrypt`, `~/docker/certbot/www` → `/var/www/certbot`
- Use `--webroot -w /var/www/certbot` (matches the HTTP-only block in `nginx-site.conf`)

After cert issuance, verify the cert chain at `~/docker/certbot/conf/live/<domain>/fullchain.pem`.

## Step 6 — nginx HTTPS Block

Now uncomment / write the HTTPS half of `templates/nginx-site.conf`, pointing at the freshly
issued cert. Reload nginx the same way as Step 4. Then verify externally:

```bash
curl -sI https://<domain>/ | head
```

Expected: 200 (or whatever the service should return), `Server: nginx`, valid TLS.

## Step 7 — Pin IP & Firewall (only if needed)

If the user said the service needs a pinned IP for DNAT or UFW rules:
1. Stop the new container, edit `ipv4_address` under the network spec
2. Add/update the matching rule in `/etc/ufw/before.rules` (NAT/FORWARD blocks — not iptables CLI)
3. `xsudo ufw reload`
4. Bring the container back up

`iptables: false` on x-server means rules must live in `before.rules`. Don't use raw
`iptables` commands — they'll be wiped on next `ufw reload`.

## Step 8 — Update Docs & CLAUDE.md

Append the new service to:
- `~/x-server-docs.md` on x-server (services table + key paths)
- `.claude/CLAUDE.md` — add a row to the "Running Services" table under X-SERVER, and any
  new paths to "Key Paths"

Don't update CLAUDE.md silently — show the diff to the operator before writing.

## Step 9 — Validate

Checklist before declaring done:
- [ ] `dig +short <domain>` returns `<WAN-IP>`
- [ ] `curl -sI https://<domain>/` returns 200 (or expected status)
- [ ] `docker compose ps` shows the service `running` and healthy
- [ ] `~/docker/certbot/conf/live/<domain>/fullchain.pem` exists and is < 24h old
- [ ] nginx access log shows the test request
- [ ] CLAUDE.md and `x-server-docs.md` updated
- [ ] If DNAT/firewall changes were needed, `xsudo ufw status verbose` shows them

## Output

Present:
1. The path of every file created/modified (compose file, nginx conf, .env, docs)
2. The exact commands run on x-server (so the operator can replay them)
3. Verification output from Step 9
4. Any deferred items (e.g. "Pinned IP not configured — add when the DNAT rule is needed")
