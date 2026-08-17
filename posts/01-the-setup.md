# Two laptops and a solar system

I ran a home lab from a shelf next to my router for seven months. February to August 2026. Two HP
laptops — a G62 from 2010 and another from 2011 — hosting a few public websites, a VPN, a private
Git server with CI, DNS for the house, file shares, and enough monitoring to wake me up when
something broke.

None of that is unusual. What made it weird was the environment, and the environment explains most
of the decisions I made, including some that look stupid without it.

The house runs on solar and the power cuts out every one to four days. I'm in Syria, so a decent
chunk of the internet just isn't reachable — GitHub's CDN, font CDNs, a couple of API providers.
And the hardware is fifteen years old with 5.6 and 3.7 GB of RAM.

Total running cost was about $10 a year. A $5 static IP from the ISP and a few dollars of
electricity a month. Everything else was free tier, because online payment from here is difficult
enough that free tier wasn't a preference.

---

## The split

One box faced the internet. Nginx, SSL, the containerized apps, WireGuard. The other one had no
port forwards pointed at it at all and ran DNS, Gitea, Samba, and a syslog receiver.

That split is the one decision I'd keep unchanged.

The public box gets attacked constantly, by everyone, from the first hour it's online. So I didn't
want anything on it that I'd be upset to lose. Gitea holding every repo I own, the DNS server the
whole house depends on, the archive of the public box's own logs — all of that sat on a machine
that had no route in from outside.

It's a harder boundary than containers or separate users. If something escapes a container on the
public box it lands somewhere holding nothing important. Getting to the second machine means owning
the first one and then pivoting across the LAN to a host that exposes nothing to the internet.

The log forwarding is the bit I'm most pleased with. The public box ships its syslog to the LAN box
over TCP. Someone who compromises the public box can wipe its local logs, but not the copies
already written somewhere they can't reach. Which is the difference between knowing what happened
and guessing.

Two machines to patch instead of one, two to back up, two that can die. Worth it.

---

## The power

Six unclean shutdowns in ten days, at the worst stretch. Battery at 24.7% of design capacity, so
no real ride-through, and a spinning Seagate from around 2010 attached to it.

The downtime never bothered me much. A personal site being unreachable for three hours is
embarrassing, not damaging. What bothered me was the hard cut — ext4 on an ageing mechanical disk
losing power mid-write, twice a week, indefinitely.

So I built a watchdog for it. `power-watchdog.service` monitored AC state and battery level, and at
15% it would hibernate the machine and set an `rtcwake` timer for 30 minutes out. The box would
wake itself up, check whether mains had come back, and either resume properly or hibernate again for
another half hour. Hands-free recovery from an outage with nobody home.

I also enabled Wake-on-LAN, which turned out to be useless. The NIC reports support for it and
`ethtool` accepts the setting, but this laptop cuts power to the ethernet controller completely on
shutdown — the link LED goes dark. No magic packet is getting through to a chip with no power. The
BIOS has no wake-on-AC option either, and suspending and plugging the charger in doesn't wake it. I
spent an evening on that before accepting it as a hardware limit.

Meanwhile I had a whole plan to move the public workload to the other laptop, whose battery was at
46.4% instead of 24.7%. Phases, rollback points, the works. Then a real outage came and took both
machines down four minutes apart, and I understood that 46% of a 2011 laptop battery buys you
minutes. The plan had been resting on something I'd never tested.

---

## The network

Some things here are blocked rather than slow. Absent.

Docker pulls ran at 9 to 14 KB/s when they ran at all, so for a while the actual procedure was:
download the image on my laptop, `scp` it to the server. Later I installed Cloudflare WARP on the
LAN box to tunnel out on demand, which worked — and introduced a fun conflict, because WARP wants
port 53 and port 53 was Pi-hole's. Updating blocklists became: stop Pi-hole, connect WARP, update,
disconnect WARP, start Pi-hole. Get that order wrong and the whole house loses DNS while you're
mid-upgrade. WARP also reroutes SSH and will drop your session, so anything long-running goes in
`tmux`. I learned that one the hard way, obviously.

A Telegram bot I'd written crash-looped every sixty seconds for two weeks before I bothered to
investigate. `api.telegram.org` is blocked. There was never going to be a fix.

An app I was hosting used the Groq API, which is also blocked, so those calls go through a tiny
Cloudflare Worker that does nothing except forward them.

And the CSP debugging was genuinely confusing for a while, because some of my font and icon
failures were policy violations and some were the network, and they look identical in a browser
console.

---

## The hardware

5.6 GB on the public box, 3.7 on the other. The entire container stack — nginx, three apps, ntfy,
Watchtower — idled at about 285 MB. That's the only reason any of it fit, and it left no room for
mistakes. One leaking container and the box starts swapping onto that ancient disk.

I found the ceiling with Nextcloud. Installed it in March, ran it for a few weeks, and it needed
three containers and 596 MB of RAM to do file sync on a 2010 Core i3. It worked in the sense that
it responded to requests. It didn't work in the sense of being something I'd use. Deleted it in
March along with its MariaDB and Redis, migrated the data to `/mnt/storage/files`, and replaced the
whole thing with Samba. Samba does 90% of what I actually wanted for approximately none of the
memory.

That was the first of eleven services I installed and then deleted. The full list is in
[post 7](07-every-problem.md) and the pattern is not flattering: I installed things because I
could.

---

## What survived

Nginx as a reverse proxy with every vhost in one monolithic config file. Behind it a static
portfolio, a Node app, and a Laravel app with SQLite, each pinned to a fixed address on a
user-defined Docker network. WireGuard native on the host rather than in a container, because it
needs kernel-level interface control and containerizing it buys nothing.

On the LAN box: Pi-hole, Gitea, a Gitea Actions runner that deployed config changes to both
machines, Samba, rsyslog, and pyLoad. All bare metal. On 3.7 GB with Gitea and Pi-hole already
resident, adding a container runtime would have cost memory for nothing.

The runner is worth flagging: it could SSH into both boxes and run sudo. So push access to the
config repo's main branch was equivalent to root on both machines. I built that on purpose and it
still deserves stating plainly, because it's the kind of thing you end up with by accident and
notice late.

---

## Things I got wrong

The split was right. Putting the site with actual visitors on the box that died twice a week was
not, and I did that for months.

Everything else in the lab tolerated downtime completely fine. Gitea being unreachable for three
hours costs nothing — I've got a clone. The file shares, same. The task app, definitely, since it
turned out nobody was using it. The portfolio was the one thing with an outside audience and it was
the single most fragile service I ran.

What took me too long was separating "do I enjoy running this" from "should this run here." Those
are different questions and I kept answering the first one and thinking I'd answered both.

The other thing: I assumed usage instead of checking it. When I finally looked, the task app had
two users and fourteen tasks and its last real visit was six weeks earlier — the traffic I'd
vaguely registered as activity was scanners sweeping for Laravel's admin path. Pi-hole, which I
thought the whole house depended on, was being queried by exactly one device, because the router
had been handing out itself as the resolver the entire time.

Both of those took five minutes to establish and I'd believed the opposite for months.

---

*Next: [Nothing Crashed](02-nothing-crashed.md).*
