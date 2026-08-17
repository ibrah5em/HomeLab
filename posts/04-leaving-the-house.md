# Leaving the house

For months I had a plan to fix the power problem, and the plan was wrong.

The public box died every one to four days when the solar cut out. The other laptop had a healthier
battery — 46.4% of design capacity against 24.7% — so the plan was to move the whole public
workload onto it. Reverse proxy, containers, VPN. I wrote it up properly: phases, rollback points,
a list of everything that would break, a note about which config was riskiest to replicate.

Then an outage came and took both machines down four minutes apart. I measured the uptimes the next
morning: 14:32 and 14:28. The battery advantage I'd spent weeks designing around bought minutes.

The plan had been resting on a premise I'd never once tested, which is embarrassing given how much
detail I'd put into everything downstream of it.

So I asked a different question. Not "which of my machines should host the site" but "should my
machines host the site."

It was a static portfolio. It had actual visitors. It needed to be up. And it was running on a
2010 laptop plugged into an unreliable solar system in a country where half the internet is
unreachable, because I like running servers.

Moved it to Cloudflare Workers in an afternoon. Proved it the same day by powering the server off
and watching the site stay up.

---

## Picking somewhere

The requirements were narrower than they sound.

It had to serve from a private repo, because I didn't want the source public. No bandwidth cap I
could get surprised by. No dependence on a student-tier benefit staying active, since those expire
and mine expires in 2027. And no build step I'd have to maintain, because it's a static site.

That ruled out more than I expected. GitHub Pages serves private repos only on a paid tier, which I
had through the Student Pack, which is exactly the thing I didn't want to depend on. Cloudflare Pages
went into maintenance mode in April 2025, so its Git integration builds Workers now anyway.

Workers with static assets it was.

## The build step I added on purpose

My repo root had a `docker-compose.prod.yml` in it with the internal Docker addresses of my home
network. Completely harmless on a LAN. Not something I wanted published to the world on every
deploy.

So even though the site needed no build, I added one — a script that assembles a `dist/` directory
containing only what should be public, and pointed Cloudflare at that instead of the repo root.

```bash
# scripts/build-static.sh
mkdir -p dist
cp index.html dist/
cp -r img fonts dist/
cp _headers robots.txt sitemap.xml dist/
# not copied: compose files, deploy configs, internal notes
```

Your publish root should be an explicit allowlist rather than "the repository." Any platform that
serves your repo root will happily serve the file you forgot was in there.

---

## Three things that went wrong

None of these were in anything I read beforehand, and together they took longer than the migration.

**A custom domain won't attach while a DNS record exists for it.** I tried to attach the apex to the
worker and Cloudflare refused, with an error that didn't explain itself. I assumed I'd
misconfigured the worker and went looking there.

The actual rule is that you can't attach a hostname as a Custom Domain while any A or CNAME record
exists for it in the zone. You delete the record first — which takes the hostname dark for however
long you take over the next step. Delete and attach back to back, have the attach screen already
open, don't do it at a busy hour.

**Stale resolvers lied to me for hours.** This cost the most and felt exactly like the platform being
broken.

I tested after the cutover and got the old server header, from nginx, on the old box. Concluded the
migration hadn't taken. Went debugging. Confirmed the same "failure" twice more over the next few
hours, from the same poisoned cache, getting steadily more convinced something was deeply wrong.

It had worked the whole time. My resolver was serving a cached answer with a long TTL.

```bash
curl --resolve example.com:443:<cloudflare-ip> https://example.com/ -I
```

That forces the connection to an address you name and ignores DNS entirely. If it comes back with
the new platform's headers, the migration worked and you're arguing with a cache. During any DNS
change your own view of the world is the least trustworthy one you have access to.

**A fresh redirect rule failed on one edge location.** I set up the `www` → apex redirect, tested it,
and one path returned a 522. Started investigating. Then retried on a hunch and it passed, then
passed nine more times consecutively.

A newly saved rule propagates across a global network and for a minute or two some PoPs have it and
some don't. A request landing on one that doesn't fails in a way that looks specific and alarming.
Retry before debugging. If it keeps failing from multiple places, then it's real.

---

## Apex and www behaved differently

The apex attached as a Custom Domain cleanly. `www` refused to, and I never got a satisfying
explanation for why.

What worked was treating them as different problems: `www` became a proxied CNAME pointing at the
apex, plus a wildcard Redirect Rule doing a real 301 with path and query preserved. Which reproduces
exactly what one line of nginx had been doing:

```nginx
server {
    server_name www.example.com;
    return 301 https://example.com$request_uri;
}
```

Two platform features to replace one directive. That's managed platforms in general — less to run,
less control over how.

---

## What broke that wasn't part of the migration

Moving nameservers killed my registrar's free email forwarding, which only works while their own
nameservers are authoritative. Nothing depended on it — my CV uses Gmail — but it's a category worth
thinking about. Things attached to your DNS provider that aren't DNS. Email forwarding, domain
privacy, registrar-level redirects. None of them show up in a migration checklist because none of
them are part of the migration.

## And the one everybody forgets

A domain that leaves your server has to leave your certbot renewal list too.

HTTP-01 works by Let's Encrypt fetching a file over HTTP from the domain, which needs the domain
pointing at your server. Once it doesn't, every renewal fails forever.

Which wouldn't matter except my renewal cron pushed an **urgent** notification on failure. So the
migration quietly installed a weekly false alarm on my phone — precisely the pattern
[post 3](03-alerting.md) is about, self-inflicted, two weeks after writing the thing about not
crying wolf.

Two monitoring scripts also still named that domain. Neither broke at cutover, because both pin to
the local nginx address rather than public DNS — so they'd have kept passing right up until the cert
lapsed, and then started reporting an expired cert every morning forever. Quiet wrongness, which is
harder to notice than loud wrongness.

Drop the name from the renewal config at cutover, not after the first alert. The cert can expire in
place; nothing's serving it.

---

## Was it right

Yes, and it wasn't close. The site has been up continuously since, through outages that would each
have taken it down for hours. Costs nothing. No server to patch, no cert to renew, no disk to fail.

The lab is where I learned how reverse proxies and certificates and container networking actually
work, and I'd do that again without hesitating. But learning how to run something isn't a reason to
keep running it. Once those came apart for me the rest of the shutdown happened fast.

---

*Next: [how to shut down a home lab](05-shutting-down.md).*
