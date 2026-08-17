# /backup — Pull Server Backups to Local Repo

Pulls weekly backup tarballs from **x-server** (default) or **n-server** down to
the matching folder under `~/HomeLab/backup/` on WSL.

**User's request:** $ARGUMENTS

## Target selection

The first word of `$ARGUMENTS` may name the target server. Everything after it is
the action.

| Form | Target | Source on server | Local dest |
|---|---|---|---|
| `/backup [action]` | **x-server** (default) | `/mnt/storage/backup/*.tar.gz` | `~/HomeLab/backup/X-server/` |
| `/backup xserver [action]` | x-server (explicit) | `/mnt/storage/backup/*.tar.gz` | `~/HomeLab/backup/X-server/` |
| `/backup nserver [action]` | **n-server** | `/var/backups/n-server/*.tar.gz` | `~/HomeLab/backup/N-server/` |

`action` is one of the shapes in the table below (defaults to "list" when absent).
So `/backup nserver latest` pulls n-server's newest; `/backup latest` pulls
x-server's.

## Why this command exists

Both servers run a weekly root-cron backup script that drops a dated tarball:

- **x-server** — `~/scripts/backup.sh`, **Tue 02:00 UTC** → `/mnt/storage/backup/`.
  Full system snapshot: docker compose + nginx.conf + banned-ips, system configs
  (sshd, ufw, wg0, samba, aide, rsyslog), systemd units, sudoers, root crontab,
  scripts, **SSH keys, certbot certs (with private keys), .env files**, nginx logs,
  ntfy config, and the kids-app database dump.
- **n-server** — `~/scripts/backup.sh`, **Wed 02:00 UTC** → `/var/backups/n-server/`
  (offset a day so the two servers never overlap). Snapshot: Gitea (consistent
  sqlite `.backup` of `gitea.db` + repos + lfs + custom + `app.ini`), Pi-hole
  (consistent `gravity.db` snapshot + `pihole.toml`), samba `smb.conf`, rsyslog
  receiver drop-in, and the root crontab.

The repo path `~/HomeLab/backup/` is **gitignored** in `.gitignore` — these archives
never reach Gitea. The folder is a local-only restore vault.

## Argument shapes

These apply to whichever target is selected.

| Arg | Action |
|---|---|
| *(none)* | List backups on the server with size + age; show what's already local; recommend an action |
| `latest` | scp the most recent tarball to the local dest |
| `all` | rsync every tarball (resumable, skips already-pulled) |
| `<filename>` | scp that specific file (e.g. `n-server-backup_2026-05-25_00-38.tar.gz`) |
| `prune` | After confirming, delete local tarballs older than the 4 newest (mirrors the server's `KEEP=4`) |
| `verify <file>` | `tar -tzf` a local tarball end-to-end to confirm it isn't truncated |

## Source of truth

| | x-server | n-server |
|---|---|---|
| Remote source | `/mnt/storage/backup/*.tar.gz` (root, 644) | `/var/backups/n-server/*.tar.gz` (homelab, 640) |
| Local dest | `~/HomeLab/backup/X-server/` | `~/HomeLab/backup/N-server/` |
| SSH alias | `x-server` (Port 2222) | `n-server` (Port 2222) |
| Retention | `KEEP=4` in `backup.sh` | `KEEP=4` in `backup.sh` |

Both archives are owned/permissioned so `homelab` can scp them without sudo
(x-server's are world-readable 644; n-server's are chowned to `homelab:homelab`
0640). The `backup.log` beside them is root-owned and must NOT be pulled.

Gitignore guard: the `backup/` line in `~/HomeLab/.gitignore` covers both
`X-server/` and `N-server/`. Verify with
`git check-ignore -v backup/N-server/<file>` if you ever doubt.

## Standard recipes

Set `SRC`, `ALIAS`, and `DEST` from the target, then the recipes are identical:

```bash
# x-server (default)
ALIAS=x-server;  SRC=/mnt/storage/backup;      DEST=~/HomeLab/backup/X-server
# n-server
ALIAS=n-server;  SRC=/var/backups/n-server;    DEST=~/HomeLab/backup/N-server
mkdir -p "$DEST"
```

### List (no args)
```bash
ssh "$ALIAS" "ls -lh $SRC/*.tar.gz 2>/dev/null"
ls -lh "$DEST" 2>/dev/null
```
Compare the two lists; tell the user which remote files are missing locally.

### Pull latest
```bash
LATEST=$(ssh "$ALIAS" "ls -t $SRC/*.tar.gz | head -1")
scp "$ALIAS:$LATEST" "$DEST"/
```

### Pull all (rsync, idempotent)
```bash
rsync -avh --progress -e 'ssh' \
  "$ALIAS:$SRC/" "$DEST"/ \
  --include='*.tar.gz' --exclude='*'
```
Don't pull `backup.log` — it's noise and would creep into the repo dir.

### Verify a tarball
```bash
tar -tzf "$DEST"/<file>.tar.gz > /dev/null && echo OK || echo CORRUPT
```

### Prune local (mirrors KEEP=4)
Show the user which files would be deleted **first**, then wait for confirmation.
```bash
ls -t "$DEST"/*.tar.gz | tail -n +5
```

## Safety rules

1. **Never `git add backup/`.** It's gitignored, but don't tempt fate with `git add -A`.
2. **Never decompress into the repo.** Extracting spills SSH private keys, certbot
   keys, `.env` files (x-server) and `app.ini`/`pihole.toml` secrets (n-server) as
   plain files. To inspect contents, extract to `/tmp/` or `~/Archive/`.
3. **Never push these to any remote, ever** — not even a "backup branch". They
   contain private keys (x-server) and the Pi-hole web-password hash + Gitea
   secrets (n-server).
4. **Don't suggest scheduling this on cron from WSL.** WSL isn't always up. If the
   user wants automation, build a pull-from-n-server flow instead (n-server is
   always up and reaches x-server fine).

## Handle the request

Parse the first word of `$ARGUMENTS` for a target (`xserver`/`nserver`); default
to x-server. Parse the remainder against the argument-shapes table. If the
remainder doesn't match a known shape, default to "list" and ask the user what
they want.

After any pull, summarize:
- What you fetched (filename + size)
- Total local count + total disk used in the target's local dest
- Whether the gitignore is still doing its job (one-liner check)
