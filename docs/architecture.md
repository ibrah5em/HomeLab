# Architecture

The design of a two-server home lab, and the reasoning behind each decision. Sanitized for
publication: addresses are illustrative, domains are placeholders, and anything credential-bearing
is described rather than shown.

---

## Topology

```
Internet
    │
    ├── app.example.com ──┐
    ├── api.example.com ──┼──► public-server :80/:443
    └── vpn.example.com ──┘
    │
Router (192.168.1.1)  ── LAN 192.168.1.0/24
    │
    ├── public-server   192.168.1.10   ← the only box reachable from the internet
    │       └── VPN subnet 10.0.0.1/24 (UDP 51820)
    │
    └── lan-server      192.168.1.11   ← dark to the WAN, no port forwards, ever
```

| | public-server | lan-server |
|---|---|---|
| Hardware | HP laptop, Core i3 (2010), 5.6 GiB | HP laptop, Core i3 (2011), 3.7 GiB |
| Storage | 224 GB SSD + 298 GB HDD | 224 GB SSD |
| Exposure | 80/443 + VPN, public | LAN + VPN only |
| Runtime | Docker | bare metal, no Docker |
| Role | reverse proxy, apps, VPN | DNS, Git, file shares, log archive |

## The central decision: isolate by machine

The public box is the one that gets attacked. Everything that would be *catastrophic* to lose in
a web compromise — the Git host with every repository, the DNS server the whole house resolves
through, the archive of the public box's own logs — lives on a different physical machine with no
route in from the internet.

This is stronger than process isolation, containers, or separate users. A container escape on the
public box reaches a machine that holds nothing irreplaceable. Reaching the LAN box requires
first compromising the public box *and then* pivoting across the network to a host that exposes
nothing to the WAN.

The cost is real: two machines to patch, two to back up, two that can fail. For a lab holding a
private Git host, it was worth it.

**The log archive is the sharpest example.** The public box forwards syslog to the LAN box. An
attacker who compromises the public box can erase its local logs, but not the copy already
written to a machine they can't reach. Configure forwarding on the **sender only** — the same
rule on both ends creates an infinite loop.

## Network design

### Container networking with the firewall in charge

The container runtime is configured with `iptables: false`. By default it writes its own firewall
rules, which fight with — and silently bypass — a host firewall. Turning that off means the
firewall config is the single source of truth.

The consequence: **NAT and FORWARD rules become your responsibility**, and must live in the
firewall's persistent config, not in ad-hoc `iptables` commands that vanish on reboot.

Two things this breaks that aren't obvious:

- Containers on the **default bridge lose outbound internet**, because the masquerade rule they'd
  normally get isn't there. Anything needing egress goes on a user-defined network that has one.
- **One-shot containers must be told which network to join** — a certificate client run with
  default networking can't reach the ACME server.

### Pinned container addresses

Every long-lived container gets a static address on the user-defined network. The reverse proxy's
config refers to backends by address, and a container restart that reassigns addresses would
otherwise silently route traffic to the wrong service. Pinning costs one line per service and
removes a whole failure class.

### VPN

WireGuard runs natively on the host, not in a container — it needs kernel-level interface control,
and containerizing it adds a networking layer for no benefit. Its masquerade and forward rules
live alongside the container ones in the firewall config.

The VPN's real purpose isn't privacy, it's **administrative access without exposing management
ports**. SSH, the DNS admin interface, and the internal notification endpoint are all firewalled
to LAN + VPN only. Nothing administrative is reachable from the internet.

## Reverse proxy

One monolithic config holding every virtual host, rather than a `sites-enabled` directory.

For a handful of sites this is *easier* to reason about — one file to read, one file to diff, one
file to roll back — and the deploy script tests it before reloading, so a syntax error can't take
the proxy down:

```bash
docker compose exec nginx nginx -t     # test
docker compose exec nginx nginx -s reload   # zero-downtime reload, not restart
```

`restart` drops connections. `reload` doesn't. The distinction matters more than it sounds.

Every server block includes a shared ban list file, so an IP banned once is banned everywhere.

## Certificates

Let's Encrypt via a containerized client using HTTP-01 webroot validation, renewed weekly by cron.

**The trap worth knowing:** HTTP-01 requires the domain's DNS to still point at this server. Move
a domain elsewhere and its renewal starts failing forever — and if renewal failure alerts you,
you've built a recurring false alarm. Remove the name from the renewal config at cutover time.

## Deployment

Config lives in a private Git repository. Pushing to the main branch triggers a self-hosted CI
runner on the LAN box, which runs a deploy script that copies configs out, validates them, and
reloads services.

**This means anyone who can push to main can run privileged commands on both machines.** That's a
real trust model and it deserves naming rather than discovering. The mitigation is discipline:
work happens on topic branches, and only reaches main after review. No auto-merge, no pushing
unreviewed work to main, no widening who can push.

Two things the deploy script learned the hard way:

- **It must merge, not overwrite, any file that is also modified at runtime.** The ban list is
  deployed from source control *and* appended to by an hourly job. Overwriting it silently
  discarded weeks of bans. It now unions both sides — a deploy can add, never remove.
- **It re-baselines the file-integrity database** after touching a monitored path. Otherwise every
  deploy leaves a "files changed" alert that re-fires nightly forever, and you learn to ignore it.

## Monitoring

Covered in depth in [post 3](../posts/03-alerting.md). The design in one line: **alert on
outcomes, digest everything else.**

- A breach detector that fires only when an exploit path returns a success status — not when one
  is merely requested
- A login watcher for authentications from outside the LAN and VPN
- Health checks every ten minutes with one-shot recovery notices, so nothing flaps
- File integrity checks daily
- One low-priority digest per day carrying everything non-urgent: security volume, top sources,
  bans, certificate expiry, backup age, patch drift

Notifications go through a self-hosted push server — one instance, two doors. Scripts publish to
it over the LAN; the phone subscribes over the WAN through the reverse proxy. Deny-all by default
with token auth in both directions. Action buttons use a **write-only token scoped to a single
topic**, so a leaked notification can't read alert history.

## What I'd change

**The isolation split was right.** I'd do it again, unchanged.

**The uptime-sensitive workload was on the wrong machine from day one.** The public site — the
only thing with an outside audience — sat on hardware dependent on my house having electricity,
in a place where that isn't a safe assumption. Everything else in the lab tolerated downtime fine.
It took months to separate "I enjoy running this" from "this should run here."

**Laptops as servers need their power reporting checked.** See
[post 2](../posts/02-nothing-crashed.md) — an old laptop misreporting wall power as battery
silently stopped all automatic security updates for weeks.
