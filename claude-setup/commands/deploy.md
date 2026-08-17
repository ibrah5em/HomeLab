# /deploy — Deploy to X-Server

Deploy a project, static site, or Docker service to x-server.

**User's request:** $ARGUMENTS

## Deployment Paths

### Static Sites
```
Local build → SCP to x-server → nginx serves from /usr/share/nginx/sites/<name>/
```
```bash
# Build locally, then:
scp -P 2222 -r ./dist/ homelab@192.168.1.10:/usr/share/nginx/sites/<site>/
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload"
```

### Docker Services
```
Local → push to Gitea → x-server pulls → docker compose up -d
```
```bash
# On x-server:
ssh x-server "cd ~/docker/<service> && DOCKER_BUILDKIT=0 docker compose pull && docker compose up -d"
```

## Pre-Deploy Checklist

1. **nginx config** — does the site have a config in `~/docker/nginx/conf.d/`?
2. **SSL cert** — does the domain have a Let's Encrypt cert?
3. **Secrets** — are they in a `.env` file (not hardcoded)?
4. **Non-root user** — Dockerfile uses `USER node` or equivalent?
5. **Volume persistence** — data volumes defined in compose, not anonymous?
6. **Network** — container connected to `docker_management`?

## Post-Deploy Checklist

1. Test nginx config: `docker compose exec -T nginx nginx -t`
2. Reload nginx: `docker compose exec -T nginx nginx -s reload`
3. Check container logs: `docker logs --tail 50 <container>`
4. Test the public URL
5. Update `x-server-docs.md`

## Syria-Specific Notes
- `DOCKER_BUILDKIT=0` required for all builds on x-server
- If service calls external APIs: check if they're blocked (Groq, Telegram, many CDNs are)
- GitHub CDN for npm packages may be blocked — build locally and `docker save | ssh | docker load` if needed

## Using tool deploy

The WSL script at `~/scripts/code-scripts/deploy.sh` handles common deploy flows:
```bash
tool deploy    # interactive deploy to x-server
```

Handle the user's deploy request. Ask for clarification if the target or type is unclear.
Show a step-by-step plan before executing anything, especially for first-time service deployments.
