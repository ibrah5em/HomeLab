# /ssl — SSL Certificate Check & Management

Check and manage SSL certificates for domains hosted on x-server.

**User's request:** $ARGUMENTS

## Domains

| Domain | Service | Cert path (in container) |
|---|---|---|
| `site.example.net` | nginx (main + notes) | `/etc/nginx/certbot-conf/live/site.example.net/` |
| `kids.example.net` | KidsApp platform | `/etc/nginx/certbot-conf/live/kids.example.net/` |

Auto-renewal: cron job runs every Sunday at 3 AM via `certbot renew`.

## Check Certificate Expiry

```bash
# Quick expiry check for all domains
for domain in site.example.net kids.example.net; do
  echo -n "$domain: "
  echo | openssl s_client -connect $domain:443 -servername $domain 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2
done
```

Or use the local tool:
```bash
tool ssl-check site.example.net kids.example.net
```

## Manual Renewal

If auto-renewal failed:

```bash
# Run certbot renew (handles all certs, use --keep-until-expiring to avoid prompts)
ssh x-server "docker run --rm --network docker_management \
  -v ~/docker/certbot/conf:/etc/letsencrypt \
  -v ~/docker/certbot/www:/var/www/certbot \
  certbot/certbot renew --keep-until-expiring --non-interactive"

# Then reload nginx
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload"
```

**Critical:** Certbot container MUST use `--network docker_management` — default bridge has no outbound internet.

## Get New Certificate (new domain)

1. Add HTTP-only nginx config first (for ACME challenge):
   ```nginx
   server {
       listen 80;
       server_name <new-domain>;
       location /.well-known/acme-challenge/ {
           root /var/www/certbot;
       }
   }
   ```
2. Reload nginx
3. Run certbot:
   ```bash
   ssh x-server "docker run --rm --network docker_management \
     -v ~/docker/certbot/conf:/etc/letsencrypt \
     -v ~/docker/certbot/www:/var/www/certbot \
     certbot/certbot certonly --webroot -w /var/www/certbot \
     -d <new-domain> --non-interactive --agree-tos -m homelab@example.com"
   ```
4. Add HTTPS block to nginx config
5. Reload nginx

## Check Cert Inside Container

```bash
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec nginx \
  openssl x509 -noout -text -in /etc/nginx/certbot-conf/live/site.example.net/cert.pem \
  | grep -E 'Not After|Subject:'"
```

## Cron Renewal Job

```bash
# Check renewal cron (runs as root)
ssh x-server "sudo crontab -l | grep cert"

# Check last renewal log
ssh x-server "sudo cat /var/log/letsencrypt/letsencrypt.log | tail -30"
```

Handle the user's SSL request. If a cert is expiring in <7 days, treat it as urgent and suggest immediate renewal.
