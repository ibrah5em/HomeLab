# DuckDNS — Subdomain Management

the operator owns the DuckDNS account behind `site.example.net` and `kids.example.net`.
DuckDNS gives 5 subdomains per account; check the dashboard before claiming a new one.

## Adding a New Subdomain

DuckDNS does not have a public API for *creating* a subdomain — only for *updating* an existing
one's IP. The creation step must be done in the web UI.

1. Go to `https://app.example.net/` and sign in (Google OAuth)
2. In the "domains" field, type the new short name (e.g. `myapp`) and click **add domain**
3. The new row shows up with `current ip` empty. Paste `<WAN-IP>` into the "current ip"
   field and click **update ip**
4. Verify from WSL — propagation is usually under 30 seconds:

```bash
dig +short <name>.example.net
# Expected: <WAN-IP>
```

If `dig` returns the wrong IP or empty, wait 60 seconds and retry. Don't move on to certbot
until DNS resolves to the right address — Let's Encrypt has hourly rate limits and a failed
issuance counts against the quota.

## Automating Future Updates (if the operator's public IP changes)

DuckDNS provides a token-based update URL. The token lives in DuckDNS dashboard → top of page.
If the home IP ever changes, ALL subdomains need updating:

```bash
TOKEN=<duckdns-token>
for sub in homelab kids-app-kids myapp; do
  curl -s "https://app.example.net/update?domains=${sub}&token=${TOKEN}&ip="
  echo
done
```

The empty `ip=` parameter tells DuckDNS to use the request's source IP. Run this from x-server
if the operator's home IP rotates (rare — ISP usually keeps it stable, but worth knowing).

## Wildcard / TXT Records

DuckDNS supports a single TXT record per subdomain via:

```
https://app.example.net/update?domains=<sub>&token=<token>&txt=<value>
```

This is what enables DNS-01 challenges for wildcard certs. Use `&clear=true` to remove the TXT
record after issuance — leaving stale ACME TXT records is harmless but messy.

## Hard Limits (DuckDNS)

- 5 subdomains per account (hard cap; not paid-tier upgradeable)
- One A record + one AAAA + one TXT per subdomain
- No CNAME support (DuckDNS does not host CNAMEs)
- No subdomain-of-subdomain (`a.app.example.net` is not supported — only `app.example.net`)

If a service needs more flexibility than this allows, the right answer is to put it on a
path under `site.example.net/<path>` rather than burning a subdomain.
