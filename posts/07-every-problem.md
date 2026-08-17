# Every problem, logged

Seven months, two servers, and everything that broke. This is the full list — not the curated
version. Some of these took an afternoon. Some took two weeks. A few I never fully root-caused and
just worked around.

The narrative versions of the best ones are in [post 2](02-nothing-crashed.md). This is the
reference: what broke, why, and what fixed it.

---

## Docker and networking

**1. Docker silently bypassed the firewall.**
Docker writes iptables rules directly and ignores UFW entirely. Every "firewalled" container port
was actually open. Fix: `"iptables": false` in `/etc/docker/daemon.json`.

**2. Which immediately killed all container outbound traffic.**
With `iptables: false`, Docker can't create its NAT rules either. No MASQUERADE for the container
subnet, and UFW's FORWARD policy is DROP. Containers couldn't reach the internet at all. Fix: NAT
and FORWARD rules written by hand into `/etc/ufw/before.rules`, referencing the bridge interface.

**3. The bridge name kept changing.**
Rules referencing the bridge broke every time the network was recreated, because Compose generates
`br-<hash>` names. Fix: pin it with `driver_opts` so it's always `br-management`.

**4. Rules in the wrong iptables chain did nothing.**
UFW's FORWARD chain drops packets before manually appended iptables rules ever run. Appending with
`iptables -A` looked like it worked and didn't. They have to go in `before.rules`.

**5. Rules targeting `docker0` didn't apply.**
Compose creates its own bridge networks. Anything written against the default `docker0` bridge is
irrelevant to a Compose container.

**6. `docker run --rm` couldn't resolve DNS.**
One-shot containers use the default bridge, which has no NAT rules — only the user-defined network
does. Certbot failed with `NameResolutionError` for a week before I connected it. Fix: always
`--network docker_management`.

**7. nginx logged the Docker gateway instead of real visitor IPs.**
Every request showed `172.18.0.1`. Docker's userland proxy does SNAT on published ports. Fix: pin
the container's address, drop Docker port publishing entirely, and DNAT in `before.rules` instead.

**8. Same problem again with DNS.**
Every DNS query logged as the bridge gateway instead of the actual device. Same cause, same fix —
pin the address, remove port publishing, DNAT.

**9. `docker compose restart` doesn't pick up new volumes.**
Added a mount, ran `restart`, nginx crash-looped on a missing file. `restart` reuses the existing
container. You need `up -d` to recreate it.

**10. A fresh named volume is root-owned.**
`_data` comes up as `root:root`. A container running as a non-root user can read it but not write.
Result: silent `EACCES` on every database save. Nothing crashed; data just never persisted. Fix:
`chown` to the container's UID before first start.

**11. Read-only volume mounts can't have subdirectories created in them.**
Hosting multiple sites, each needing its own directory under a `:ro` mount. Fix: mount the sites
to a separate writable path.

**12. BuildKit produced broken images.**
Silently incomplete `node_modules` after `npm ci` — no error, app failed at runtime. Never fully
root-caused it on a 2010 CPU. Fix: `DOCKER_BUILDKIT=0`.

**13. A third-party tool couldn't talk to the Docker daemon.**
Bundled an old SDK that negotiated an API version the newer daemon refused. Opaque error. Fix:
pin `DOCKER_API_VERSION` as an environment variable on the container.

**14. That same tool had no outbound access.**
It sat on the default bridge, which — see #2 — has no NAT. It fell back to a slower path and
logged warnings I wasn't reading. Fix: move it to the user-defined network.

**15. Stale DNAT rules survived a firewall reload.**
Changing DNAT rules and reloading left old entries live. I spent an hour debugging a rule that no
longer existed in any file. Fix: `iptables -t nat -F PREROUTING` before reloading.

## nginx and TLS

**16. Heredocs mangled the config.**
Writing `nginx.conf` via `<< EOF` escaped `$` and `;` characters. Config looked fine in the editor
and was subtly wrong on disk. Fix: quoted delimiter, and `cat -n` the result before reloading.

**17. CSS served as plain text.**
Missing `include mime.types`. The site rendered completely unstyled and the logs showed `200 OK`
for everything.

**18. CSP blocked the icon font and web fonts.**
`style-src` and `font-src` only allowed `'self'`, so an external icon CDN and Google Fonts silently
failed. Fix: whitelist both. Related: the icon library was loaded with `preload` plus an inline
`onload` handler, which CSP also blocked — replaced with a plain stylesheet link.

**19. CSP blocked the site's own inline script.**
Mobile nav and theme toggle stopped working. Inline scripts need `'unsafe-inline'` (no) or a
SHA-256 hash. Used the hash — with the caveat that it changes whenever the script changes.

**20. Certificate renewal reloaded nginx the wrong way.**
The cron used `docker compose restart`, which drops connections. Changed to
`exec -T nginx nginx -s reload`.

**21. A retired domain kept failing renewal.**
Moved a domain to another host and left it in the certbot `-d` list. HTTP-01 needs the domain
pointing at your server, so every weekly run failed — and the cron pushed an *urgent* alert on
failure. Self-inflicted weekly false alarm.

**22. Certificate directories are root-owned.**
Scripts checking whether a cert already exists need `sudo test -d`, or they always think it
doesn't.

**23. Certbot prompted interactively inside a cron job.**
Fix: `--keep-until-expiring`.

## DNS

**24. `systemd-resolved` fights for port 53.**
Standard conflict. Disabled it — then discovered that disabling isn't enough: it comes back and
grabs the port the moment the DNS service restarts. It has to be **masked**.

**25. The DNS server silently dropped cross-subnet queries.**
Queries arriving from the LAN to a container address were discarded with no log line, because
dnsmasq defaults to `LOCAL` listening mode. The v5 environment variable for this is silently
ignored in v6 — it needs `pihole-FTL --config dns.listeningMode all`.

**26. The installer bound to the wrong interface.**
It picks the first available one. The VPN tunnel was up during install, so it bound to the tunnel's
address instead of the LAN.

**27. Wi-Fi showed a "no internet" warning on every device.**
The ad-blocker was blocking connectivity-check domains. Fix: whitelist
`connectivitycheck.gstatic.com`, `captive.apple.com`, `msftconnecttest.com`.

**28. Blocklist updates failed — country-level blocking.**
Several list sources are GitHub-hosted and GitHub's CDN is blocked here. Fix: a tunnel, on demand.

**29. Which then took port 53.**
The tunnel client grabs 53, conflicting with the DNS server. The documented procedure became: stop
DNS, connect tunnel, update, disconnect tunnel, start DNS. Get the order wrong and the whole house
loses name resolution.

**30. The tunnel also reroutes SSH and drops your session.**
Learned this mid-upgrade. Everything long-running now goes in `tmux`.

**31. Blacklisted domains in the wrong table.**
Individual entries stored in the adlist table instead of the domain list produced "invalid
protocol" errors on every gravity update. Harmless but noisy. Fix: delete rows where the address
doesn't start with `http`.

**32. Config format changed between major versions.**
v6 uses `pihole-FTL --config`. Environment variables and `setupVars.conf` from v5 are ignored
without warning. Also `pihole update` doesn't exist — it's `pihole -up`.

## Power and hardware

**33. The server reported wall power as battery.**
`/sys/class/power_supply/AC*/online` read `0` while plugged in, battery at 100%, weeks of uptime.
This silently stopped `unattended-upgrades` on every run — it defaults to `OnlyOnACPower "true"`.
Drifted **88 security updates** behind including openssl, curl and the kernel, with
`reboot-required` never set. The only evidence was one line in a log:
`WARNING System is on battery power, stopping`. Fix: `OnlyOnACPower "false"` — these are stationary
boxes and the reading is noise.

**34. `apt upgrade` never installs a new kernel.**
A kernel bump is a *new package name*, and `upgrade` doesn't install new packages. You need
`full-upgrade` and then an actual reboot.

**35. Wake-on-LAN doesn't work if the NIC loses standby power.**
Supported by the NIC, enabled correctly, completely non-functional from a powered-off state,
because the hardware cuts power to the ethernet controller. No BIOS option for wake-on-AC either.
Workaround: hibernate plus an `rtcwake` cycle, so the machine wakes itself periodically and comes
back on its own after an outage.

**36. Power cuts every one to four days.**
Solar. Six unclean shutdowns in ten days at the worst point, on a battery at 24.7% of design
capacity with an ageing spinning disk attached. Built a watchdog that hibernates at 15% battery
with a 30-minute wake cycle. Ultimately solved by moving the workload off the machine entirely.

**37. The battery plan was based on an untested premise.**
I spent weeks designing a migration to the other server because its battery was healthier. Then a
real outage took **both boxes down four minutes apart**. 46% of design capacity buys minutes.

## Storage and data

**38. Samba exposed the entire home directory.**
`.ssh/`, the env file holding sudo passwords, cached git credentials, every service `.env` — all
readable by anything on the LAN with the share password. Replaced with a single scoped share.

**39. Samba ignored the VPN interface.**
`bind interfaces only` makes Samba skip the WireGuard interface entirely. Fix: remove it, add the
VPN subnet to `hosts allow`.

**40. Samba has a separate password store.**
Adding a system user doesn't create a share user. `smbpasswd -a`, then `smbpasswd -e`.

**41. A "backup" directory on the same disk as its source.**
Both copies, one failure domain. Found during decommissioning, which is a lucky place to find it.

**42. The self-hosted cloud was too heavy for the hardware.**
Three containers and 596 MB of RAM on a machine with 5.6 GB total and a 2010 CPU. Replaced with
Samba, data migrated to the bulk disk. Its database and cache containers went with it.

**43. A verification method that invented a data-loss scare.**
Comparing two 133 GB trees directory-by-directory reported **2,124 missing files**. Every one was
present — the tree had been reorganized, and a path-level diff can't see a move. Fix: compare
content manifests (name + size), not paths. Full story in
[post 5](05-shutting-down.md).

**44. A deploy that silently discarded weeks of data.**
The IP ban list was deployed from source control *and* appended to by an hourly job. Every deploy
reset it to the last committed version. It was never empty, just mysteriously short. Fix: union
both sides so a deploy can only add.

## Monitoring and alerting

**45. Alerting on attempts instead of outcomes.**
Every scan generating a notification. Muted the channel within a week, which is worse than no
monitoring because you believe you're covered. Rebuilt around "did an exploit path return 2xx".

**46. Single-page apps return 200 for every unknown path.**
Which makes an exploit probe against an SPA look exactly like a successful breach. The response was
byte-identical to the site root — that's the tell. Fix: deny known-bad paths at the proxy so they
403 before reaching the app. Requires remembering to do it on every new vhost, which makes it a
fragile fix.

**47. I investigated my own public IP as an attacker.**
It appeared repeatedly in the access logs. It was me.

**48. Alerts hardcoded credentials in three separate scripts.**
Consolidated into one `chmod 600` env file loaded by all of them.

**49. The file-integrity monitor fired after every deploy.**
Legitimately — the deploy touches monitored paths. But an alert that fires every time you deploy is
an alert you learn to ignore. Fix: re-baseline automatically at the end of a deploy that wrote to
a monitored path.

**50. Monitoring scripts kept referencing a domain that had moved.**
Both pinned to the local proxy address rather than public DNS, so neither broke at cutover — they'd
just start silently reporting nonsense once the vhost was deleted. Quiet wrongness is worse than
loud wrongness.

## SSH and system

**51. Ubuntu 24.04 uses socket-based SSH.**
`ssh.socket` overrides the port in `sshd_config`. Changing the port does nothing until you disable
it — and disabling isn't enough, because it gets re-enabled on reboot. It has to be masked.

**52. UFW won't delete a rule the way you added it.**
`ufw delete allow <port>` fails for rules with source restrictions. You have to repeat the full
original specification.

**53. `vbetool dpms off` hangs in a systemd unit.**
Used for turning the screen off on a headless laptop. Fix: write to `intel_backlight` under
`/sys/class/backlight/` instead.

**54. The power button shut the server down.**
logind's default. Fix: `HandlePowerKey=ignore` and hand it to acpid, which toggles the screen
instead. Left lid-open doing nothing deliberately — it's the emergency escape hatch when SSH is
unavailable.

**55. System service accounts had login shells.**
Fix: `usermod -s /usr/sbin/nologin`.

## CI/CD

**56. The CI runner didn't survive reboots.**
Installed manually, ran as an orphan process, no persistence. Deleted and reinstalled properly as
a systemd unit.

**57. Runner labels must match the execution mode.**
Running in host mode (no Docker), every label has to be `<name>:host`. A `:docker` label makes it
try Docker and fail.

**58. The runner ignored its config file.**
The bare `daemon` command doesn't read the config unless you pass `-c`. Without it, it falls back
to built-in defaults — which assume Docker — and breaks on a box that doesn't have it.

**59. Config schema drifts between patch versions.**
Fix: generate the config with the exact pinned binary rather than copying an example, and pin the
runner version to the server version.

**60. No JS actions available.**
No Node on the box, so no `actions/checkout` and no marketplace actions. Workflows use plain `git`
in `run:` steps.

**61. No workflow-dispatch API on that Git host version.**
The endpoint 404s — it landed in a later release. Manual runs come from the web UI, or by pushing
a commit that matches the path filter.

**62. A backup script aborted on a directory that no longer existed.**
Retired a site, left the path in the backup list, and the whole backup started failing. Silent,
because success was silent and I'd only wired an alert for a non-zero exit that never came.

## Country-level

**63. GitHub's CDN is blocked.**
Docker pulls at 9–14 KB/s where they worked at all. Workaround: download on the laptop, `scp` to
the server. Later: an on-demand tunnel.

**64. `api.telegram.org` is blocked.**
A bot container crash-looped every ~60 seconds for two weeks before I looked into it properly.
Removed.

**65. An AI API provider is blocked.**
An app's features silently failed. Fix: proxy the calls through a small edge worker.

**66. Font and icon CDNs are blocked or unreliable.**
Combined with #18 and #19, this made CSP debugging genuinely confusing — some failures were policy,
some were the network.

**67. DNSSEC validation fails intermittently.**
ISP DNS interception.

**68. Online payment is difficult.**
Which is why every piece of this ran on free tiers: free dynamic DNS, free certificates, reused
hardware. Total running cost was about **$10/year** — a $5 static IP and a few dollars of
electricity a month.

---

## Things I installed and deleted

Not problems exactly, but worth logging. Eleven services that didn't survive:

| Service | Why it went |
|---|---|
| Self-hosted cloud (+ its DB and cache) | Too heavy — 3 containers, 596 MB, on a 2010 i3 |
| Dashboard | Never looked at it |
| Web file browser | Unused |
| Container management UI | CLI was faster |
| Uptime monitor | Overkill for two machines |
| Web terminal | Crash-looped, exit 127 |
| File sync | Never used it |
| Telegram bot | Country-blocked |
| Torrent client | Closed the only public-facing port |
| Password manager + its proxy | Replaced with a local app |
| Digital garden | Retired |

The pattern is obvious in hindsight: I installed things because I could, not because I needed
them. The ones that survived to the end — reverse proxy, DNS, Git host, notifications, VPN — were
all things I'd actually reach for.

---

*Back to the [series index](../README.md).*
