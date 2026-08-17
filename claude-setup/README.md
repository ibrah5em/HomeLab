# The agent setup

This is the `.claude/` folder that ran the lab — 36 files, ~4,000 lines, sanitized. Context file,
five scoped agents, thirteen slash commands, four skills.

Copy it to `.claude/` in a repo and it works. But the files matter less than the handful of ideas
underneath them, so those are first.

The narrative version, including the password experiment, is in
[post 6](../posts/06-the-agent-knew-more.md).

---

## The ideas

### Documentation with an actual reader gets maintained

This is the whole thing, really.

I'd written docs before. They rotted, because nobody read them — including me. `CLAUDE.md` gets
read at the start of every single session, which means a wrong line in it produces a wrong answer
*today*. So it got fixed. Not out of discipline; out of self-interest.

Seven months later that file was the only complete description of the lab that existed. Not a
side effect of the setup — the main output of it.

### Write the gotcha the day it burns you, with the why

Roughly a third of the context file is a list of things that had already gone wrong. Each entry
says what happened, why, and what to do instead:

```markdown
- **Docker iptables: false** → NAT/FORWARD rules MUST be in /etc/ufw/before.rules,
  NOT iptables CLI
- **nginx reload** → always `docker compose exec nginx nginx -s reload`, never restart
- **`docker compose restart`** → does NOT pick up new volume mounts; use `up -d`
```

Every tutorial online says `restart`. I never once had to re-explain that, because the file said
otherwise and the file gets read first. Compressed institutional memory, and it's the highest-value
part of the whole setup by a wide margin.

### State hard rules as hard rules

Some things aren't preferences. They're near the top, blunt, with reasons:

```markdown
### 🚫 Hard rule: this repo is NEVER on GitHub or any public site
### 🚫 Hard rule: history is sacred — never rewrite, never force
### 🚫 Hard rule: new top-level folders need approval before push
```

That last one has saved me more than once. Any brand-new top-level directory stops before staging
and asks — which catches project copies and scratch dirs before they land in the repo.

Vague guidance gets averaged away. "Never force-push, not even `--force-with-lease`" doesn't.

### One agent per machine

Five agents, each scoped: one per server, one for deploys, one for monitoring, one for security
review. "Why is the site down" goes to something that already knows the container names, the
pinned addresses, and where the logs live.

The point isn't capability, it's not having to re-establish context. And an agent scoped to one box
can't casually touch the other.

### Slash commands are runbooks that happen to be executable

`/status`, `/deploy`, `/logs`, `/ssl`, `/firewall`, `/backup` — each one a markdown file describing
a procedure. `/status` means "SSH both boxes, check containers, disk, certs, backup age, tell me
what's actually wrong."

The same file is documentation and implementation. It can't drift from itself.

### Skills for chains with an order you'll forget

Adding a site to the server had a specific sequence: DNS record, HTTP-only vhost for the ACME
challenge, deploy, run certbot, *then* the HTTPS vhost, deploy again, update the docs. Skip a step
and certbot fails in a way that isn't obviously about ordering.

`skills/new-service/` walks it, with reference docs and templates. Written once, at a moment when
I understood the ordering, for every later moment when I wouldn't.

### Document how the credential moves, never the credential

The pattern is in the context file. The value never is:

```bash
source ~/.server-creds.env
ssh public-server "sudo -S <command>" <<< "$PUBLIC_SERVER_SUDO"
```

`sudo -S` takes the password on stdin, the here-string feeds it, so it never reaches a command
line, a process list, or shell history. The agent uses the pattern without ever reading the file.
It held for seven months against a deliberately weak password —
[post 6](../posts/06-the-agent-knew-more.md) has the details.

### Name your trust boundaries out loud

```markdown
### ⚠️ Trust model: push to `main` = arbitrary sudo on both servers
```

A CI runner watched this repo and ran deploy scripts with sudo on both machines. So push access to
main was root on both boxes. Written down explicitly, with the mitigation next to it: topic
branches, review, then merge. No auto-merge.

You end up in situations like this by accident. Writing it down is what turns an accident into a
decision.

---

## Structure

```
CLAUDE.md              context: topology, services, paths, hard rules, gotchas
agents/                5 scoped agents — per-server, deploy, monitoring, security
commands/              13 slash commands, each a runbook
skills/
  new-service/         the full add-a-site chain + templates
  incident-triage/     cross-server "what just happened"
  extend-claude/       how to add to this setup, with templates
  remember/            curated saves (see the note below)
```

## Using it

```bash
cp -r claude-setup /path/to/your/repo/.claude
```

Then rewrite `CLAUDE.md` for your own infrastructure — it's the only file that's genuinely
mine rather than reusable. The addresses in it are placeholders (`192.168.1.10`, `example.com`,
`<WAN-IP>`) and every one needs replacing.

`agents/` and `commands/` are close to reusable if your setup is also "nginx and Docker on a box
you SSH into." `skills/extend-claude/` is fully generic — it's the meta-skill for adding more of
these, with templates and a quality checklist.

**A note on `skills/remember/`:** it manages an auto-memory system I decided *not* to use. The
context file says so explicitly — durable facts go in `CLAUDE.md` or the docs, not scattered
memory entries, because one version-controlled source of truth beats several unversioned ones.
The skill is here because it's a reasonable reference implementation, but it contradicts the rest
on purpose. Read the reasoning before adopting it.

## What I'd change

**Keep a paper copy of the topology.** I stopped holding it in my head. That's fine until the thing
you're debugging is network access to the machine that has the context.

**Split the context file sooner.** It reached ~500 lines and was doing four jobs: topology,
conventions, gotchas, and trust model. Splitting it earlier would have kept the gotcha list — the
most valuable section — from getting buried in the middle.
