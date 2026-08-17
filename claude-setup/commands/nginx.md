# /nginx — Nginx Management on X-Server

Manage nginx on x-server. Nginx runs inside Docker container `nginx-ssl` as part of `docker_management` network.

**User's request:** $ARGUMENTS

## Critical Rules

1. **Reload ≠ Restart.** Always reload: `docker compose exec nginx nginx -s reload`
   - Restart stops nginx → site goes down during restart
   - Reload is zero-downtime and the correct approach
2. **Test before every reload.** Always run `nginx -t` first
3. **Config location:** `~/docker/nginx/conf.d/` on x-server
4. **Logs location:** `~/docker/nginx/logs/` on x-server
5. **Certs:** `/etc/nginx/certbot-conf/live/<domain>/` inside the container (mounted from `~/docker/certbot/conf/`)

## Common Operations

### Reload nginx (safe, zero-downtime)
```bash
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -t && docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload"
```

### View nginx config for a site
```bash
ssh x-server "cat ~/docker/nginx/conf.d/<site>.conf"
```

### List all site configs
```bash
ssh x-server "ls -la ~/docker/nginx/conf.d/"
```

### View access logs (live)
```bash
ssh x-server "tail -f ~/docker/nginx/logs/access.log"
```

### View error logs
```bash
ssh x-server "tail -50 ~/docker/nginx/logs/error.log"
```

### Add a new site
When adding a new site:
1. Create HTTP-only config first (for ACME challenge)
2. Test + reload
3. Run certbot for the domain
4. Add HTTPS block to config
5. Test + reload

**Always use `-T` flag with `docker compose exec` in scripts** (no TTY needed).

### SSL cert check
```bash
ssh x-server "echo | openssl s_client -connect <domain>:443 -servername <domain> 2>/dev/null | openssl x509 -noout -dates"
```

## nginx.conf Gotchas
- `map {}` blocks: single-quoted regex only (double quotes cause "invalid number of parameters")
- PCRE2: no `\.\.\\` — use separate patterns for traversal variants
- `script-src` in CSP blocks inline `onload=` handlers
- Don't add CSP headers in nginx for apps that use Helmet — causes duplicate headers
- `include mime.types` is required or CSS is served as `text/plain`

Handle the user's request using the above context. If they want to edit a config, show the proposed changes and ask for confirmation before applying.
