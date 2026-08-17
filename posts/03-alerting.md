# Alerting that doesn't cry wolf

Put a server on the internet and it gets scanned immediately. Not occasionally — continuously, from
the first hour, forever. Requests for `/wp-login.php` on a box that has never run WordPress. Probes
for `/.env` and `/phpMyAdmin`. Bare IP addresses in the Host header. Bytes that aren't HTTP at all.

My first monitoring setup told me about all of it. I muted the channel within a week, which left me
with monitoring that produced nothing while I believed I was covered. That's worse than having none.

Rebuilding it around a narrower question is the most useful thing I did in the whole lab. Not "is
someone attacking me" — someone is always attacking you. "Did an attack work?"

---

## Outcomes, not attempts

A scan for `/.env` that gets a `404` tells you nothing except that the internet exists. The same
request returning `200` means somebody is reading your environment file right now.

So the detector tails the access log and fires only when a path from a known-bad list returns a 2xx.
Everything else — thousands of probes a day — goes into a digest at low priority that doesn't buzz
the phone.

That took my alert volume from unusable to roughly zero, which for a small server on a quiet week is
the correct number.

## Then it started reporting breaches

The alert said a known-bad path had returned `200` on one of my services. Real path, real success
code, real service. By my own logic somebody was inside.

Nobody was inside.

A single-page app behind a reverse proxy returns `200` and its `index.html` for every unknown path.
That's how client-side routing works — the server can't know which paths the JavaScript router
considers real, so it serves the shell for all of them and lets the browser sort it out.

So a probe for `/phpinfo` against an SPA vhost gets a `200`, from a path on the known-bad list, with
a real response body. The detector's logic was correct. Its inputs were lying to it.

I hit this through ntfy's own web UI. `/phpinfo` returned `200` with a 2,504-byte body. The thing
that gave it away, once I bothered to look, was that the body was byte-identical to the site root. It
wasn't a phpinfo page. It was ntfy's homepage, served to a URL that doesn't exist.

Two ways to tell them apart, both quick. Real phpinfo output is tens of kilobytes of dense tables;
an SPA shell is small and identical for every unknown path. So:

```bash
curl -s -o /dev/null -w '%{size_download}\n' https://example.com/
curl -s -o /dev/null -w '%{size_download}\n' https://example.com/phpinfo
```

Same byte count as your homepage means it *is* your homepage. And then actually fetch it and read
it, because thirty seconds of looking beats any amount of inferring from status codes.

The fix is to deny the known-bad paths at the proxy so they never reach the app:

```nginx
if ($bad_uri) { return 403; }
if ($bad_qs)  { return 403; }
```

Now the probe gets a `403`, the detector sees a blocked request, nothing fires.

I'm not entirely happy with it, though. Every new SPA or proxied vhost has to carry that same deny
block, and if I forget one the whole false-positive class comes back — on a service I just deployed,
at the exact moment I'm least likely to distrust an alert. A fix that depends on remembering
something forever isn't really a fix. It's in my documentation as a known fragility rather than a
solved problem.

---

## Shadow mode

New detectors run for a while logging `WOULD ALERT` instead of actually pushing anything.

This sounds obvious. I only did it because an earlier version had already burned me, and it paid off
immediately — the SPA thing surfaced during a shadow period instead of at 3am.

You can't work out a detector's false-positive rate by reading its code. You have to watch what it
would have woken you for, against real traffic, for longer than feels necessary.

---

## Auto-banning, and what it doesn't catch

An hourly job bans repeat offenders. More than 20 responses with status 403 or 444, within the last
5,000 log lines.

The part worth writing down isn't the rule, it's what the rule deliberately ignores:

404s, because a probe for something I never had isn't much evidence and counting them would ban half
the internet. Anything under 20 hits. Address-rotating scanners, which never accumulate a count
against any single address and are therefore structurally invisible to this. And anything that
scrolled out of the window — a slow scan spread over a week never has 20 hits inside 5,000 lines.

Six months later "why wasn't this address banned?" is a question you will definitely ask, and having
the answer written next to the code is the difference between thirty seconds and an afternoon.

There's also a bug in how that ban list got *deployed* that took me weeks to spot — the deploy
script quietly reverting it every run. That's in [post 2](02-nothing-crashed.md).

---

## The channel itself

Self-hosted ntfy. One instance, two doors: scripts on the LAN publish to it directly, my phone
subscribes over the internet through nginx with WebSocket upgrade. Anything missed while the phone
is offline backfills from the container's cache on reconnect.

Locked down both directions — `auth-default-access: deny-all`, token auth to publish or subscribe,
anonymous access gets a `403`. Alert bodies contain attacker addresses and service status and I'd
rather that stayed on hardware I own than on a public instance.

The detail I'd actually recommend copying: the one-tap action buttons use a separate publish-only
token, scoped to a single command topic. Not the admin token.

An alert arrives saying a container is down, with a `[Restart]` button. Tapping it publishes a
command to a topic that a listener daemon acts on. If that notification is sitting on my lock screen
in a café and somebody picks up the phone, the worst they can do is restart a container. They can't
read my alert history, because that token has no read access to anything at all.

Least privilege on a notification button feels like overkill until you picture the phone on a table.

---

## One message a day

Everything non-urgent goes into a single daily digest at low priority so it doesn't buzz. Security
volume and top sources, addresses banned, days until certs expire, backup age, pending security
updates, whether the running kernel is current.

That last item exists because of the silent patch-drift incident in [post 2](02-nothing-crashed.md).
Once burned, permanent fixture.

Everything reduces to one thing: if routine information buzzes your phone, you will mute the
channel, and then you'll miss the one that mattered. Urgent has to mean a human needs to act now.
Everything else gets a digest to live in.

That split is the difference between monitoring I trust and monitoring I've silenced.

---

*Next: [leaving the house](04-leaving-the-house.md).*
