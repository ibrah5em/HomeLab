# /update-docs — Auto-Update Homelab Docs From Session

Review the current session's work and update the relevant doc file(s) in `~/HomeLab/docs/` based on what was actually touched.

**User's request:** $ARGUMENTS

## Doc Files

| File | Scope |
|---|---|
| `~/HomeLab/docs/x-server-docs.md` | Anything on x-server: nginx, Docker services, WireGuard, certbot, UFW, ntfy, server-cmd, nginx-watcher, AIDE, backups |
| `~/HomeLab/docs/n-server-docs.md` | Anything on n-server: Pi-hole, Gitea, Samba, rsyslog receiver, WARP usage |
| `~/HomeLab/docs/system-docs.md` | WSL/local box: zsh config, `~/scripts/`, `~/tools/`, `~/.claude/`, NVM/uv, Ollama, aliases |

## Auto-Detect Which Doc(s)

Scan this session's history for signals. Update a doc only if its scope was actually touched:

- **x-server-docs.md** — `ssh x-server`, paths starting `~/docker/`, references to nginx-ssl/kids-app/ntfy containers, `/etc/wireguard/`, `/etc/ufw/before.rules`, certbot, x-server systemd units (nginx-watcher, server-cmd, dailyaidecheck), x-server cron jobs
- **n-server-docs.md** — `ssh n-server`, `pihole`, `/etc/pihole/`, Gitea, `/etc/gitea/`, Samba, `smbpasswd`, `/etc/rsyslog.d/`, `/var/log/remote/`, `warp-cli`
- **system-docs.md** — edits to `~/HomeLab/`, `~/.claude/`, `~/scripts/`, `~/tools/zsh/`, `~/.zshenv`, `~/.zshrc`, alias changes, new WSL tooling, Ollama/Open WebUI on dev box

If nothing falls into a scope, say so and exit without writing.

## What To Write

**Do** add:
- New services/containers/peers/sites that were created
- New file paths, ports, or config locations introduced
- Non-obvious gotchas discovered (the kind that belong in the "Burned Before" list)
- Workflow changes (e.g., "Pi-hole update now needs WARP because…")
- Renamed/removed/relocated artifacts

**Don't** add:
- Ephemeral debugging commands you ran
- Status checks that just confirmed health
- Restatements of facts already in the doc
- One-off investigations with no lasting change
- Anything you'd write in a commit message but not a runbook

If the session was pure investigation with no infra change, write nothing and report "no doc-worthy changes."

## Procedure

1. **Identify target doc(s)** from the signals above. If ambiguous, ask the user.
2. **Read the target doc** before editing — match its existing structure (sections, table style, code-block conventions).
3. **For each change, find the right section** (don't append to the bottom blindly). Examples:
   - New container → "Running Services" table + a paragraph in the relevant section
   - New gotcha → existing "Gotchas" / "Key Notes" list
   - New workflow → existing "Common Workflows" section
4. **Show the user a preview** — list each doc you're about to edit and the bullet summary of what's being added/changed.
5. **Wait for confirmation**, then apply edits with `Edit` (not `Write` — preserve everything else).
6. **Commit and push to Gitea** (see Push step below).
7. **Report** which docs were updated, which sections changed, and the commit hash.

## Push Step (always runs after edits)

`~/HomeLab/` is a git repo with a Gitea remote (`http://192.168.1.11:3000/homelab/homelab.git`).
After applying doc edits:

```bash
cd ~/HomeLab
git status --short                   # show what's staged + unstaged + untracked
```

**Before staging, check for untracked top-level folders.** If `git status` shows any new top-level
directory that isn't gitignored, STOP and follow the "new top-level folders need approval" rule
in CLAUDE.md — ask the operator before adding.

If only the doc files changed (and no new folders):

```bash
cd ~/HomeLab
git add docs/<file1>.md docs/<file2>.md     # stage only the docs you edited
git commit -m "docs: <one-line summary of what changed>"
git push                                     # silent — credentials cached
```

Commit message style: `docs: <subject>` — short, imperative, names what changed. Examples:
- `docs: add nginx-watcher allowlist for Syrian ranges`
- `docs: x-server — note BuildKit disabled gotcha`
- `docs: n-server — Pi-hole gravity bumped to 621k`

If the push fails (network, Gitea down), report the error and tell the operator the commit is local
only — he can retry with `cd ~/HomeLab && git push` later.

## Reminder
This repo is **private Gitea on LAN**, not GitHub. Never suggest GitHub URLs, `gh` CLI, or
public-repo workflows here. See CLAUDE.md "HomeLab Repo Rules" for the full hard-rules list.

## Style Rules

- Match the doc's existing tone (terse, runbook-style, tables for inventories, `$` only when distinguishing input from output)
- Use the same fenced-code-block language tags the doc already uses
- Preserve the table column order if adding rows to an existing table
- Date-stamp only entries that are explicitly time-bound (e.g., "as of 2026-05-13") — most facts shouldn't be dated
- Never rewrite sections wholesale just to "tidy up" — touch only what the session changed
