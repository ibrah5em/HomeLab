# The agent knew my servers better than I did

I ran both servers with an AI agent sitting next to me the whole time. Not for writing code —
for operations. Deploys, nginx changes, firewall rules, debugging at midnight when something
stopped responding.

By about month three it knew the infrastructure better than I did. That's not a compliment to the
AI. It's what happens when you write everything down for something else to read, and then stop
being the one who remembers.

I also ran a small experiment on it: I gave both servers a deliberately terrible sudo password and
watched whether the agent ever leaked it. That's the second half of this post and it's the part I
was least sure about going in.

---

## The setup

Everything lived in a `.claude/` folder in the config repo. Three things in it:

**`CLAUDE.md`** — the context file. Loaded at the start of every session. Network topology, both
servers' addresses and ports, what runs where, which paths matter, and a long list of things that
had already burned me. Every gotcha in [post 2](02-nothing-crashed.md) was in there, written the
day it happened.

**Agents** — small scoped definitions. One that only touched x-server, one for n-server, one for
monitoring, one for security auditing. So "check why the site is down" went to something that
already knew the container names and where nginx logs live.

**Slash commands** — `/status`, `/deploy`, `/logs`, `/ssl`, `/backup`, `/firewall`, `/pihole`,
`/gitea`, `/ntfy`, `/vpn`. Each one a markdown file describing a runbook. `/status` meant "SSH both
boxes, check containers, disk, certs, backup age, and tell me what's wrong."

None of it is clever. It's a runbook that happens to be readable by something that can also execute
it.

## The part I didn't expect

The context file started as notes for the AI. It ended up being the only complete description of
the lab that existed anywhere.

I'd fix something at 1am, write two lines about it in `CLAUDE.md` so the agent wouldn't suggest the
broken approach again, and move on. Six weeks later I'd have completely forgotten the fix — but
I'd ask about it and get it back, verbatim, because I'd written it down for a reader who never
forgets.

That inverts something. I'd always treated documentation as a chore you do for other people or for
future-you, and future-you never reads it. Writing it for an agent that reads it *every single
session* changed the incentive. The file got maintained because it had a consumer.

The failure mode is obvious in hindsight and I walked straight into it: I stopped holding the
topology in my head. Ask me in April what IP nginx was pinned to and I'd have said "let me check."
The agent would just say `172.18.0.100`. That's fine right up until the thing you're debugging is
why you can't reach the agent's machine.

## What it was actually good at

Cross-server correlation, mostly. Something alerts on one box, the logs live on the other because
of syslog forwarding, and the fix is in a config file in the repo on a third machine. Holding all
three at once is exactly the thing I'm bad at at midnight.

Also: not forgetting the gotchas. There's a rule in my setup that nginx gets `nginx -s reload` and
never `restart`, because restart drops connections. I've never once had to re-explain that. Every
tutorial on the internet says `restart`. The agent said `reload`, every time, because the context
file said so.

Where it was weaker: anything requiring physical presence, obviously. And it was confidently wrong
about my hardware more than once — it'd reason from how servers normally behave, and these are two
laptops from 2010 and 2011 that don't. The battery misreporting wall power ([post 2](02-nothing-crashed.md))
took a while precisely because "the machine is lying about its power state" isn't in anyone's
training data as a likely cause.

---

## The password experiment

Here's the question I actually wanted answered: **can an AI agent operate two servers without
leaking the credentials to do it?**

So I set it up to fail. Both boxes got the same sudo password — same password, both machines,
which is bad practice on its own — and the password itself was short and weak. Genuinely weak. If
it ever appeared anywhere, it was over.

That was the control. If the mechanism worked with a bad secret, it works with a good one. And if
it leaked, I'd know immediately because the password was so guessable that any exposure was total.

### The mechanism

The password lives in a file, `chmod 600`, never committed. Every privileged command goes through
this shape:

```bash
source ~/.server-creds.env
ssh x-server "sudo -S <command>" <<< "$PUBLIC_SERVER_SUDO"
```

Three things about that:

`sudo -S` reads the password from stdin instead of a terminal. The here-string `<<<` feeds it in.
So the password **never appears in the command line** — which means it never lands in `ps` output,
never in shell history, never in a process list that another user on the box could read.

The variable is expanded by my local shell before the SSH command is built, so the agent writes
`"$PUBLIC_SERVER_SUDO"` and never sees what it contains.

And the thing that surprised me: **the agent never needed to know the value.** Not once in seven
months. It knew the *pattern* — source this file, use this variable name, pipe it this way. It
never had a reason to read the file, so it never did.

### Did it hold?

Yes. I checked the obvious places — shell history, process lists, the repo, session transcripts.
The password never showed up in any of them.

What I got wrong: I'd assumed the risk was the agent being careless with a secret it held. The
actual risk turned out to be somewhere else entirely.

### The real hole was somewhere else

Two of them, in fact, and neither was the agent.

**The Samba share.** An early config exposed my entire home directory over the LAN as a network
drive. That directory contained `.ssh/`, the env file with those sudo passwords, cached git
credentials, and every service's `.env`. Anything on my network with the Samba password could read
all of it. The careful stdin mechanism was protecting a file that was also sitting on a Windows
network drive.

Removed it, replaced with a single explicitly-scoped share pointing at one folder. A share whose
scope is "my home directory" is a share whose scope is everything.

**The deploy pipeline.** A CI runner watching the config repo, which on a push to main SSHes into
both machines and runs privileged commands. Which means push access to that branch is equivalent
to root on both boxes.

That one I built deliberately and it still deserves saying out loud, because it's easy to end up
there without noticing. The mitigation isn't technical — work goes on a topic branch, gets
reviewed, then merges. No auto-merge, no pushing straight to main.

### What I actually concluded

The agent was never the weak link. The mechanism held for seven months against a password so bad
it should have leaked from anywhere.

But that's a narrower finding than "AI can handle servers securely." What it really shows is that
**how the secret moves matters more than the secret** — and that if you get the mechanism right,
the human process around it becomes the interesting attack surface. My leaks were a file share I
misconfigured in week two and a trust boundary I built on purpose.

I wouldn't recommend the weak password. That was a test condition and I changed it later, after it
turned up in a repo's git history — which is its own story about how secrets escape through paths
you weren't watching.

---

## Would I do it again

Yes, with one change: I'd keep a printed copy of the network layout somewhere physical.

The rest of it worked. The context file is the single most valuable artifact the lab produced —
more than any config, because configs describe what a system *is* and that file describes why it's
that way and what already went wrong. It's the reason this series exists at all. Every post here
is downstream of notes I wrote so an agent wouldn't repeat my mistakes.

The whole `.claude/` structure is in the config repo. Sanitized versions of the runbooks it drew on
are in [`docs/`](../docs/).

---

*Series index: [README](../README.md). If you only read one, make it
[Nothing Crashed](02-nothing-crashed.md).*
