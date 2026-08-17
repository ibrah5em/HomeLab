# Scripts

Operational scripts from the lab, genericized. These ran in production for months against real
traffic on a public-facing server.

All hardcoded addresses, container names, domains and paths have been lifted into a config block
at the top of each file, or into environment variables. Nothing here reads a credential from
anywhere but a file you create yourself.

## Setup

```bash
cp ntfy.env.example ~/.config/ntfy-token.env
chmod 600 ~/.config/ntfy-token.env
# then edit it with your tokens
```

Every script sources that one file for notification credentials. Nothing else is shared.

## The scripts

### `ntfy-send.sh`

Push notification sender — priority, tags, and optional one-tap action buttons.

The idea worth stealing: the action button publishes using a **separate, publish-only token**
scoped to a single command topic, never the admin token. A notification sitting unlocked on a
phone screen therefore can't be used to read your alert history.

```bash
./ntfy-send.sh "Container Down" "app-one exited" urgent "skull" "restart:app-one"
```

### `server-health.sh`

Disk, container, and HTTP-liveness checks. Run every 10 minutes from cron.

Two things that make it survivable rather than annoying:

- **Cooldowns.** A condition alerts once, then goes quiet for an hour. Without this, one stuck
  container buzzes you every ten minutes until you mute the channel — and a muted channel is
  worse than no channel at all.
- **One-shot recovery notices.** When a condition clears you get exactly one "recovered" message
  and the cooldown resets. Nothing flaps.

The HTTP check exists because a container status check can't see the case that actually happens
most: the container is `running` and the app inside it is wedged. It probes the real
proxy→app path with correct SNI, and treats any 2xx/3xx/4xx as alive — only no-response or 5xx
counts as down.

### `ban-ip.sh`

nginx-level IP banning: a file of `deny` directives included in every server block, with nginx
config-tested before each reload so a bad entry can't take the proxy down.

`auto-ban` bans addresses producing more than 20 blocked (403/444) responses in the last 5,000
log lines. **Read the semantics comment at the top of the file** — it's deliberately blind to
404s, low-volume probes, and address-rotating scanners, and knowing what a rule *doesn't* catch
matters more than knowing what it does.

There's a warning in there worth repeating: if this ban file is also deployed from source
control, your deploy must **merge** rather than overwrite, or every deploy silently discards
every ban added since the last commit. That bug ran for weeks before I spotted it. The story is
in [post 2](../posts/02-nothing-crashed.md).

## Not included

**The daily digest script.** It's the best idea in the set — one low-priority message a day
carrying security volume, top sources, bans, certificate expiry, backup age and patch drift, so
that everything non-urgent has somewhere to go that isn't your lock screen. But the implementation
is welded to specific service names, certificate paths and log formats, and a genericized version
would be a rewrite rather than a port.

The design is described in [the public server runbook](../docs/public-server-runbook.md) and
[post 3](../posts/03-alerting.md) if you want to build your own. The principle is one line:
**everything that isn't a genuine emergency goes in the digest.**

## License

MIT — see [LICENSE](../LICENSE).
