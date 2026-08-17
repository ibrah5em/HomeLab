# HomeLab

Seven months of running a two-server home lab off a pair of old HP laptops in Syria —
February to August 2026 — and the decision to shut it down.

This repo is the public write-up: what I built, what broke, what I'd do differently, and the
operational scripts that turned out to be worth keeping. The lab itself is retired. That's not
the disappointing part of the story; it's the point of it.

---

## The short version

Two laptops next to a router:

- **A public-facing box** — nginx reverse proxy with SSL termination, Docker services behind it,
  WireGuard VPN, a self-hosted push-notification server, and a set of monitoring daemons that
  watched the access logs for actual break-ins rather than the constant background noise of
  scanners.
- **A LAN-only box, dark to the WAN** — DNS with ad-blocking, a private Git host, file sharing,
  and a syslog archive that received the public box's logs so there was a record that survived
  the public box.

Three constraints shaped nearly every decision:

1. **Power.** A solar system that cut out every one to four days. The public-facing box took an
   unclean shutdown each time, on a battery at 24.7% of its design capacity, with a ~15-year-old
   spinning disk attached.
2. **The network.** Running from Syria means GitHub's CDN, font CDNs, and several API providers
   are blocked outright. Some of the architecture exists purely to route around that.
3. **The hardware.** A 2010 Core i3 and a 2011 Core i3. 5.6 GiB and 3.7 GiB of RAM. Everything
   had to fit in that, and some things didn't.

It worked. Then the reason it existed stopped applying, so I moved the services that needed
uptime to infrastructure that doesn't depend on my house having electricity, verified everything
was saved, and turned the machines off.

## Why write it up

Most home-lab content is a build log that ends at "and it works." The parts I found hardest to
learn — and hardest to find written down — were the failures that *don't announce themselves*,
and the judgement call about when self-hosting stops being worth it.

Both are in here.

---

## The series

| # | Post | Status |
|---|---|---|
| 1 | [Two laptops and a solar system](posts/01-the-setup.md) — the setup, and the three constraints that shaped every decision | Written |
| 2 | **[Nothing Crashed](posts/02-nothing-crashed.md)** — the bugs that cost me the most time, and why none of them threw an error | **Written** |
| 3 | [Alerting that doesn't cry wolf](posts/03-alerting.md) — breach detection, and why my monitor kept reporting break-ins that weren't | Written |
| 4 | [Leaving the house](posts/04-leaving-the-house.md) — migrating to an edge platform, and three gotchas that cost real time | Written |
| 5 | [How to shut down a home lab](posts/05-shutting-down.md) — verifying 133 GB before deleting it, and the false alarm that nearly cost me a week | Written |
| 6 | [The agent knew my servers better than I did](posts/06-the-agent-knew-more.md) — running the lab with an AI agent, and a deliberately weak password that never leaked | Written |
| 7 | [Every problem, logged](posts/07-every-problem.md) — all 68, unabridged | Written |
| 8 | [Everything reported clean](posts/08-everything-reported-clean.md) — four bugs in the checker that was supposed to make this repo safe to publish | Written |

Start with **Nothing Crashed** if you only read one. It's the most useful standalone piece and
needs no context from the others.

## Documentation

The **complete** operational runbooks — not summaries. These are the documents the lab actually
ran on, ported in full with identifying values substituted. A real runbook shows more about how a
system was run than any amount of prose about it.

- [Architecture overview](docs/architecture.md) — topology, network design, and the reasoning (written for this repo)
- [Public server runbook](docs/public-server-runbook.md) — ~1,350 lines: nginx, Docker, SSL, VPN, firewall, monitoring, every command
- [LAN server runbook](docs/lan-server-runbook.md) — ~850 lines: DNS, Git hosting, CI, file shares, log archive

What was substituted: public addresses, hostnames, MAC addresses, account names, third-party
project names, and absolute paths. What was kept: internal RFC1918 addresses, the full service
inventory, firewall rules, container layout, and every gotcha — because that's the useful part.

[`tools/scrub-check.sh`](tools/scrub-check.sh) enforces 14 checks across the whole repo and is
run before every commit.

## The agent setup

The `.claude/` folder that ran the lab — [`claude-setup/`](claude-setup/), 37 files, ~4,000 lines.
Context file, five scoped agents, thirteen slash commands, four skills. Copy it to `.claude/` and
it works, but [its README](claude-setup/README.md) leads with the ideas rather than the files —
why documentation with a reader gets maintained, writing gotchas the day they burn you, and
documenting how a credential moves without ever documenting the credential.

## Scripts

Operational scripts from the lab, genericized into configurable form. These ran in production for
months against real traffic.

- [`ntfy-send.sh`](scripts/ntfy-send.sh) — push notifications with priority, tags, and one-tap action buttons backed by a least-privilege token
- [`server-health.sh`](scripts/server-health.sh) — container, disk and HTTP-liveness checks with cooldowns and one-shot recovery notices
- [`ban-ip.sh`](scripts/ban-ip.sh) — nginx-level IP banning with an auto-ban mode driven by access-log analysis

See [`scripts/README.md`](scripts/README.md) for configuration — and for why the daily digest
script isn't included, though its design is documented.

---

## A note on what's here and what isn't

This repo is a **derived** artifact. The lab's actual documentation lived in a private repository
on the LAN Git host and stays there — it carries real addresses, ports, credentials paths, and a
deploy trust model that has no business being public.

Everything here has been rewritten or scrubbed for publication, and
[`tools/scrub-check.sh`](tools/scrub-check.sh) enforces it. If you're doing something similar,
that separation is worth copying: never make the private repo public, write a public one.

## License

Scripts are MIT — see [LICENSE](LICENSE). Take them, they're more useful to you than to me now.
The written posts are © Ibrahem Hasaki; ask before republishing in full, quote freely with credit.
