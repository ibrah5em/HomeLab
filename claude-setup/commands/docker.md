# /docker — Docker Management on X-Server

Manage Docker containers and services on x-server (192.168.1.10).

**User's request:** $ARGUMENTS

## Context

All Docker services live in `~/docker/` on x-server. The main compose file is at `~/docker/docker-compose.yml`.

**Critical rules:**
- NEVER use `docker compose restart nginx` — use `docker compose exec nginx nginx -s reload` for zero-downtime reloads
- NEVER use `docker run --rm` for nginx config testing — use `docker compose exec nginx nginx -t`
- Certbot containers MUST use `--network docker_management` flag
- `DOCKER_BUILDKIT=0` is required on x-server (BuildKit has npm ci bug + no --network support)
- All compose networks use bridge `docker_management` with subnet `172.18.0.0/16`
- Container IPs are pinned in docker-compose.yml for DNAT rules

**Common compose locations:**
```
~/docker/docker-compose.yml         ← main compose (nginx, ntfy, kids-app)
~/docker/nginx/conf.d/              ← nginx site configs
~/docker/nginx/logs/                ← nginx access/error logs
~/docker/certbot/conf/              ← Let's Encrypt certs
~/docker/ntfy/                      ← ntfy config + data
```

**Common operations to handle:**

If the user asks to:
- **list containers** → `ssh x-server "docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"`
- **restart a service** → `ssh x-server "cd ~/docker && docker compose restart <service>"` (for non-nginx services)
- **reload nginx** → `ssh x-server "docker compose -f ~/docker/docker-compose.yml exec nginx nginx -s reload"`
- **test nginx config** → `ssh x-server "docker compose -f ~/docker/docker-compose.yml exec nginx nginx -t"`
- **view logs** → `ssh x-server "docker logs --tail 50 -f <container>"`
- **rebuild a service** → `ssh x-server "cd ~/docker && DOCKER_BUILDKIT=0 docker compose build <service> && docker compose up -d <service>"`
- **check volumes** → `ssh x-server "docker volume ls | grep -v '^DRIVER'"` 
- **system cleanup** → `ssh x-server "docker system prune -f"` (warn: removes stopped containers + dangling images)
- **pull new images** → `ssh x-server "cd ~/docker && docker compose pull"`

Execute the relevant operation and report the output clearly.
If the request is ambiguous, ask for clarification before running anything destructive.
