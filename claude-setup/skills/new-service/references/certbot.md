# Certbot — Issue & Renew Certs on x-server

Certbot runs as a one-shot Docker container that joins the `docker_management` network so it
can reach `nginx-ssl` to validate the ACME challenge. Certs and ACME state live on the host
under `~/docker/certbot/` and are mounted into both certbot and nginx.

## Prerequisites Before Calling Certbot

1. The HTTP-only nginx block from `templates/nginx-site.conf` is live and `nginx -t` passes
2. `~/docker/certbot/www/` exists and is writable (it's created by the existing nginx setup)
3. `dig +short <domain>` returns `<WAN-IP>` (DuckDNS propagation took effect)
4. Port 80 is open and reachable from the public internet (not firewalled per-IP)

## Issue a New Cert (webroot mode)

```bash
ssh x-server "docker run --rm \
  --network docker_management \
  -v /home/homelab/docker/certbot/conf:/etc/letsencrypt \
  -v /home/homelab/docker/certbot/www:/var/www/certbot \
  certbot/certbot certonly \
    --webroot -w /var/www/certbot \
    -d <DOMAIN> \
    --email <EMAIL> \
    --agree-tos --no-eff-email \
    --non-interactive"
```

After success, the cert chain is at `~/docker/certbot/conf/live/<DOMAIN>/fullchain.pem` and
the private key at `privkey.pem` on the host (mounted into nginx as `/etc/letsencrypt/...`).

## Add an HTTPS Block & Reload nginx

Uncomment Phase 2 of `templates/nginx-site.conf` (matching the just-issued cert paths), then:

```bash
ssh x-server "docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -t \
  && docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload"
```

## Renewal

Weekly cron (Sun 03:00 UTC) already runs:

```
docker run --rm --network docker_management \
  -v /home/homelab/docker/certbot/conf:/etc/letsencrypt \
  -v /home/homelab/docker/certbot/www:/var/www/certbot \
  certbot/certbot renew --quiet \
  && docker compose -f /home/homelab/docker/docker-compose.yml exec -T nginx nginx -s reload
```

Success/failure pings the `security-alerts` ntfy topic via `~/scripts/ntfy-send.sh`. No
per-domain action needed — once a new cert is issued, renewal picks it up automatically.

## Force Renewal (for testing or near-expiry)

```bash
ssh x-server "docker run --rm --network docker_management \
  -v /home/homelab/docker/certbot/conf:/etc/letsencrypt \
  -v /home/homelab/docker/certbot/www:/var/www/certbot \
  certbot/certbot renew --force-renewal --cert-name <DOMAIN>"
```

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| `Failed to connect to <domain> for HTTP-01` | DNS not propagated or port 80 blocked | `dig` + `curl -sI http://<domain>/.well-known/acme-challenge/test` |
| `unauthorized: Invalid response` | nginx HTTP block missing or pointing to wrong root | Confirm `location /.well-known/acme-challenge/ { root /var/www/certbot; }` exists |
| `connection refused` | nginx-ssl not on docker_management network | `docker network inspect docker_management` — fix compose if missing |
| Wildcard requested but using webroot | webroot can't validate wildcards | Switch to `--manual --preferred-challenges dns` (DuckDNS supports TXT) |

Never run certbot with `--network bridge` (default). The `docker_management` network is required to reach nginx-ssl by container name.
