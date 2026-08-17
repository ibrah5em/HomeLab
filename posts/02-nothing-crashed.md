# Nothing crashed

The bugs that cost me the most time all had one thing in common. Nothing crashed. No error page, no
failed health check, no alert. Something quietly wasn't happening and every indicator I had said
things were fine.

Here are the worst ones from seven months of running two old laptops as servers.

---

## The server that thought it was on battery

There was no symptom. That's the whole problem.

I checked the patch level one day for no particular reason and the public-facing box was **88
security updates behind**. Openssl, curl, cups, the kernel. `unattended-upgrades` was installed,
enabled, and had been applying nothing for weeks. `/var/run/reboot-required` had never been created,
so every time I'd checked whether a reboot was needed, the answer had been a confident no.

The other server, identical config, was completely current.

I figured the service had died. It hadn't — `systemctl status` was green, the timer was firing on
schedule, everything normal. Took me a while to think of reading the log, because why would you read
the log of a thing that says it's working.

```
WARNING System is on battery power, stopping
```

`unattended-upgrades` ships with `OnlyOnACPower "true"`, which is a completely sensible default —
don't drain a laptop battery installing packages. And this laptop reports:

```bash
$ cat /sys/class/power_supply/AC*/online
0
```

Zero. Plugged into the wall. Battery sitting at 100% and "fully-charged", machine showing weeks of
uptime. The hardware just lies about it, `unattended-upgrades` believes the hardware, and every run
aborts before doing anything at all. The newer laptop reads `1` correctly, which is exactly why it
stayed patched and why this looked like a software problem for so long.

The fix is one line:

```bash
# /etc/apt/apt.conf.d/99-homelab-nobattery
Unattended-Upgrade::OnlyOnACPower "false";
```

These boxes don't move and they're on mains. The battery reading is noise.

Then I hit the second half of it. `apt upgrade` will not install a new kernel, ever, because a
kernel bump arrives as a new package name — `linux-image-6.8.0-<something>` — and `upgrade` doesn't
install new packages, only upgrades existing ones. You need `full-upgrade`. And then an actual
reboot, which on a machine with weeks of uptime and a dying battery is its own small event.

If you run a laptop as a server, go check this now. It takes one command:

```bash
grep -i battery /var/log/unattended-upgrades/unattended-upgrades.log | tail
```

---

## The VPN that broke my LAN underneath the routing table

From Windows, `ping 192.168.1.1` returned "General failure." Couldn't reach my router, either
server, or anything else on my own network. From a WSL terminal on the same physical machine, `ssh`
and `scp` to those same servers worked perfectly.

Same box. Same network. One environment could see the LAN, the other couldn't.

I assumed routing and added an explicit static route for the local subnet:

```
route add 192.168.1.0 mask 255.255.255.0 <gateway> -p
```

Nothing. A textbook on-link route, correctly installed, completely ignored. That's the bit that
eventually told me routing wasn't where the problem was.

I was on ProtonVPN's free tier. Free ProtonVPN uses WireGuard, and it sets `AllowedIPs = 0.0.0.0/0`
— everything. When WireGuard's Windows driver sees a catch-all `AllowedIPs`, it installs a WFP
filter that blocks all untunneled traffic. That's WireGuard's own kill switch, built into the
driver, and it's a completely separate thing from the kill-switch toggle in ProtonVPN's UI. I turned
that toggle off. It changed nothing, because it was never the thing doing this.

WFP drops the packet at send time, below routing. Which is why my perfectly good static route lost
— the kernel picked the route, and then the filter threw the packet away afterward. And why WSL kept
working: WSL2 traffic rides Hyper-V's virtual switch on a different adapter and never touches that
filter at all.

ProtonVPN has an "Allow LAN connections" setting that fixes this properly. It's Plus-only. I
switched to Windscribe, whose free tier lets LAN traffic through, and that's still what I use.
Failing that, do your server admin from WSL, or just disconnect for the few minutes you need the
LAN.

The takeaway I actually use: when a correct route doesn't work, stop staring at routes.

---

## Docker's firewall rules aren't where you think

Docker writes iptables rules directly and ignores UFW completely. So every container port I thought
was firewalled was open. The fix is `"iptables": false` in `/etc/docker/daemon.json`, which hands
the responsibility back to me.

And immediately broke all container outbound traffic, because with `iptables: false` Docker also
can't create the NAT rules that let containers reach the internet. No MASQUERADE for the container
subnet, and UFW's FORWARD policy is DROP. So I had to write NAT and FORWARD rules by hand into
`/etc/ufw/before.rules`.

Which is where they have to live, incidentally. Rules added with `iptables -A` look like they work
and vanish on the next reboot. Worse, UFW's FORWARD chain drops packets *before* manually appended
rules ever get evaluated, so they can appear to work and not work depending on what you're testing.

Then a few related things fell out of it over the following weeks:

Certbot stopped being able to resolve DNS. `docker run --rm` uses the default bridge, which has no
NAT rules — only my user-defined network does. Every cert request failed with `NameResolutionError`
for about a week before I connected the two facts. Every one-shot container needs
`--network docker_management`.

Watchtower couldn't reach the registry for the same reason, but instead of failing it fell back to a
slower path and logged warnings I wasn't reading.

Rules referencing the bridge kept breaking whenever the network got recreated, because Compose
generates `br-<hash>` names. Pinned it with `driver_opts` so it's always `br-management`.

And nginx logged `172.18.0.1` as the client address for every single visitor, because Docker's
userland proxy does SNAT on published ports. Fixed by pinning nginx's container address, removing
Docker's port publishing entirely, and doing DNAT in `before.rules` instead. Then I did the same
thing again for Pi-hole a week later, having apparently learned nothing the first time.

One more: if you change DNAT rules, stale entries survive a `ufw reload`. Flush them first or you'll
spend an hour debugging a rule that doesn't exist in any file:

```bash
sudo iptables -t nat -F PREROUTING && sudo ufw reload
```

---

## The volume that was readable but not writable

An app saved data. The save appeared to work. On restart the data was gone.

A fresh Docker named volume has its `_data` directory owned by `root:root`, mode 755. My container
ran as a non-root user — `node:18-alpine` has a built-in `node` user at UID 1000 — and that user can
read the volume fine. It cannot write to it.

So every read worked, the app started clean, health checks passed, and every write failed with
`EACCES` that the app swallowed silently. The casualty was a SQLite save, but this hits anything
doing log rotation or write-temp-then-rename.

```bash
sudo chown -R 1000:1000 /var/lib/docker/volumes/<volume>/_data/
```

Before first start, not after.

Related, and this one I hit while adding the ban-list file: `docker compose restart` does not pick
up new volume mounts. It restarts the process inside the existing container. nginx crash-looped on
a file that wasn't there and I spent an embarrassing amount of time checking whether the file was
there on the host. `up -d` recreates the container. `restart` doesn't.

---

## The deploy that quietly undid three weeks of bans

My favourite, because the bug was in the thing whose entire job was keeping the system consistent.

An hourly job scanned nginx access logs and banned repeat offenders — anything producing more than
20 blocked responses in the last 5,000 log lines got appended to a `banned-ips.conf` that every
server block includes. Over weeks that built up into a real list.

I also had a deploy script that pushed configs from the repo to the server. Including
`banned-ips.conf`.

So every deploy reset the ban list to whatever the repo last had, throwing away everything added
since. And because the auto-ban job would slowly rebuild it, the list was never empty — just
mysteriously shorter than I expected, and only right after a deploy. It took me weeks to put those
two facts next to each other.

The fix was making the deploy incapable of removing anything:

```bash
# a deploy can only ADD bans, never drop them
sort -u <(ssh "$SERVER" "cat $REMOTE_BANS") "$LOCAL_BANS" > "$MERGED"
```

There's a real cost to that. Un-banning now means removing the address from both the server and the
repo, or the next deploy brings it back. I'd still take it over silent data loss.

The general version, which I've since found useful elsewhere: if a file is both deployed from source
control and modified at runtime, you have this bug. Either the deploy merges, or the file shouldn't
be in source control.

---

## Shorter ones

**BuildKit produced broken images.** `npm ci` completed successfully and produced subtly incomplete
`node_modules`. No error, app failed at runtime. `DOCKER_BUILDKIT=0` fixed it and I never root-caused
it properly — on a 2010 CPU I stopped caring once builds worked.

**Heredocs mangled my nginx config.** Writing `nginx.conf` via `<< EOF` escaped `$` and `;`. Looked
right in the terminal, was wrong on disk. Quote the delimiter and `cat -n` the result.

**Missing `include mime.types` served CSS as plain text.** The site rendered completely unstyled and
every log line said `200 OK`.

**Log forwarding config goes on the sender only.** Putting the same rsyslog rule on both machines
creates an infinite loop where each forwards to the other forever. Disk fills fast.

**`systemd-resolved` will fight your DNS server for port 53** and disabling it isn't enough. It
comes back and grabs the port the next time Pi-hole restarts. It has to be masked.

**Ubuntu 24.04 uses socket-based SSH.** `ssh.socket` overrides the port in `sshd_config`, so
changing the port does nothing. And disabling the socket isn't enough either — it gets re-enabled on
reboot. Mask it.

**UFW won't delete a rule the way you added it.** `ufw delete allow 8000` fails for rules with
source restrictions. You have to repeat the entire original specification.

**Wake-on-LAN doesn't work if the NIC loses standby power.** Fully supported, correctly enabled,
completely non-functional, because the hardware kills power to the ethernet chip on shutdown.

---

## What they have in common

Every one of these reported success while doing nothing. `unattended-upgrades` exited zero every
run. The volume write "succeeded." The deploy "worked." Nginx logged `200`.

And in most of them my first plausible theory was wrong in a way that cost more than the bug did.
The static route was correct. The service really was running. The file really was on the host.

The signal usually existed, in a log I had no reason to read. One WARNING line explained months of
missing security patches.

What I do differently now is check the outcome rather than the exit code. Not "is the update service
running" but "what's the patch count." Not "did the deploy succeed" but "does the file on the server
say what I think it says." Not "is the container up" but "is the thing it should have written
actually there."

---

*Next: [alerting that doesn't cry wolf](03-alerting.md) — why my breach detector kept reporting
break-ins that hadn't happened.*
