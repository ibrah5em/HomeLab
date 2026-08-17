# How to shut down a home lab

There are thousands of guides for building one of these. I couldn't find a single one for ending it,
which is odd, because decommissioning is the only phase with a step you can't undo.

Break nginx during the build and you fix nginx. Delete 133 GB and discover the copy was incomplete
and that's the end of it.

---

## Knowing it's over

No dramatic failure. Just a slow accumulation of things that didn't need to be there.

The site had moved to the edge and was obviously better off. The VPN hadn't been used in months.
Then I checked two things properly for the first time.

The task app — a Laravel thing I'd built and deployed and felt good about — had 2 users and 14 tasks,
and its last real browser session was six weeks earlier. The traffic I'd been vaguely aware of was
scanners sweeping for Laravel's admin path. Requests to `/dashboard` redirecting to `/login`, from
addresses in Bulgaria and Germany, where I have no users.

And Pi-hole, which I thought the whole house depended on, had been queried by exactly one device.
The router had been handing out itself as the resolver the entire time. 143 queries in 24 hours,
against a gravity list of 621,000 domains.

Both took five minutes to check. I'd assumed the opposite for months, and the assumption was
flattering in both cases, which is probably not a coincidence.

---

## Order

Everything is reversible except deleting data. So: verify, then archive, then wipe. And don't overlap
them — don't start wiping one thing while still verifying another, because that's how you delete the
wrong copy while distracted.

---

## The verification mistake

This is the part worth the post, because my method was wrong in a way that looked completely
reasonable.

133 GB on the server's spinning disk, already copied to an external drive months earlier. To confirm
before wiping, I compared the two trees directory by directory — size and file count per folder.

| Folder | Server | Copy | |
|---|---|---|---|
| Design | 2.9 G / 7,845 | 3.5 G / 7,992 | fine |
| Documents | 4.1 G / 4,889 | 34 G / 11,260 | fine |
| Music | 35 G / 5,125 | 35 G / 5,143 | fine |
| IT | 90 G / 4,071 | 90 G / 1,947 | ⚠️ |
| Temp | 2.4 G / 1 | missing | ⚠️ |

2,124 files missing. Same total size in `IT`, half the file count. Three subfolders apparently gone
entirely. It looked exactly like a copy that had silently truncated partway through.

Every single file was already there.

Months earlier I'd reorganized the drive and moved a whole subtree out of `IT/` and into
`Documents/`. Which is precisely why `Documents` had grown from 4,889 files to 11,260 while `IT`
appeared to shrink by a matching amount. Those two numbers were the same event. The missing 2.4 GB
video was in the recycle bin, deleted deliberately.

A path-level comparison cannot see a move. When a file goes from `A/x` to `B/x`, a per-directory diff
reports it missing from A and surplus in B — two separate observations in two separate rows that
never visibly cancel out. Scan a reorganized tree and you get a long list of missing files and a
vague sense that some folders got bigger, and nothing connects them for you.

What actually works is comparing content manifests instead of paths:

```bash
find /source -type f -printf '%f|%s\n' | sort -u > source.txt
find /copy   -type f -printf '%f|%s\n' | sort -u > copy.txt
comm -23 source.txt copy.txt
```

Path-independent, so a move is invisible to it. Which is the point. That resolved 2,124 missing files
to zero in one pass.

The worse mistake was that I started copying the "missing" files back before I'd finished
diagnosing. So then I had duplicates on the drive, which had to be verified byte-identical with
`diff -rq` and removed — cleanup created entirely by acting on a bad finding. Reaching the wrong
conclusion cost me nothing. Acting on it cost an hour.

When a verification tells you you've lost data, check the verification first.

---

## What to keep

I swept the actual disks rather than trusting my own documentation, and found things nobody
remembered.

A Docker volume for a Telegram bot whose container had been deleted months earlier, still holding
`tasks.db` and `notes.db`. Not in any service list, because the service didn't exist. A retired
site's files sitting in `~/docker/website.retired-20260523/`, untouched for a quarter. The nginx
access logs, which are the only copy of the entire security record. The ufw `before.rules` file,
which — because Docker was configured not to manage iptables — was the only place on the machine that
described how the network actually worked. And a 76 MB dataset that couldn't be regenerated because
it was a point-in-time pull.

Also a directory called `backups` sitting on the same disk as the thing it was backing up. Both
copies, one failure domain. Found it during the sweep, which is a lucky place to find it.

Your service list describes what you remembered to write down. The volumes and the orphaned
directories and the `/mnt` subfolders describe what's actually there. Those are different sets.

What I skipped on purpose: expiring certificates, rebuildable images, Pi-hole's gravity database
(100 MB+ and regenerates from the adlists), the AIDE baseline, and SSH host keys, which should never
be reused anyway.

The archive came out at about 100 MB from both machines. Checksummed where checksums already
existed. The most important file in it is a README explaining what everything else is and why it's
there, because an archive you can't navigate in two years is the same as no archive.

---

## The stuff not on the machines

The parts I nearly forgot, because they don't live on either server.

Router port forwards — remove them. Leaving forwards pointed at a freed address means whatever gets
that address next by DHCP inherits them. The certbot cron, disabled before it starts failing weekly.
DNS repointed on the one device that was still using Pi-hole. And a GitHub Actions runner registered
against someone else's repository, which would otherwise sit permanently offline in their settings.

Verify the port forwards from *outside* your network. A request from inside can hairpin through the
router and succeed against a forward that's already gone, which will tell you the opposite of the
truth. I confirmed mine by fetching a unique path from an external host and grepping the access log
for it. It never arrived, while internal health checks kept logging normally every ten minutes. That
combination is proof.

---

## What the documentation becomes

My config repo now describes infrastructure that doesn't exist. That's fine — it's a record.

But the deploy pipeline in it is dead, the "push to main runs sudo on both servers" trust model
describes machines that are being wiped, and every skill and command assumes live hosts. So the top
of that file now says exactly that, before anything else, splitting what's historical from what still
binds. Not because I'll forget. Because the version of me who opens it in a year, in a hurry, won't
read past the first screen.

---

## The ending

I didn't shut it down because it failed. I shut it down because I finally stopped answering two
questions as though they were one.

Do I enjoy running this — yes, genuinely, and it taught me more about reverse proxies, certificates,
container networking and firewalls than any amount of reading would have.

Should this be running here — no. Not on a 2010 laptop on a solar system that fails twice a week in
a country where half the internet is blocked, serving a site with real visitors.

Both of those were true the entire time. Building the lab was right and ending it was right. The only
mistake was the months I spent letting the first answer settle the second one.

---

*Next: [the agent knew my servers better than I did](06-the-agent-knew-more.md) — seven months of
running the lab with an AI agent, and a deliberately weak password that never leaked.*
