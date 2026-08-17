# /gitea — Gitea Management on N-Server

Manage Gitea self-hosted Git server on n-server (192.168.1.11:3000).

**User's request:** $ARGUMENTS

## Architecture

- **Binary:** `/usr/local/bin/gitea`
- **User:** `gitea` (system user, shell: `/usr/sbin/nologin`)
- **Data:** `/var/lib/gitea/`
- **Config:** `/etc/gitea/app.ini`
- **Database:** SQLite3 at `/var/lib/gitea/data/`
- **Web UI:** http://192.168.1.11:3000
- **Mode:** Offline (OFFLINE_MODE = true)

## Common Operations

### Service Management
```bash
ssh n-server "sudo systemctl status gitea"
ssh n-server "sudo systemctl restart gitea"
ssh n-server "sudo journalctl -u gitea -f --no-pager -n 50"
```

### Check Config
```bash
ssh n-server "sudo cat /etc/gitea/app.ini"
```

### Backup Gitea
```bash
ssh n-server "sudo -u gitea gitea dump -c /etc/gitea/app.ini -w ~/backups/"
```
Creates a zip in `~/backups/` containing repos, config, and database.

### Create/List Repos (via API)
```bash
# List all repos
curl -s http://192.168.1.11:3000/api/v1/repos/search \
  -H "Authorization: token <GITEA_TOKEN>" | python3 -m json.tool | grep full_name

# Create new repo
curl -X POST http://192.168.1.11:3000/api/v1/user/repos \
  -H "Authorization: token <GITEA_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"<repo-name>","private":false}'
```

## Git Workflow (from WSL)

```bash
# Add Gitea as origin (primary)
git remote add origin http://192.168.1.11:3000/homelab/<REPO>.git

# Add GitHub as mirror (when needed)
git remote add github https://github.com/homelab/<REPO>.git

# Push to Gitea
git push origin master

# Push to GitHub mirror
git push github master

# Save credentials (uses personal access token, not password)
git config --global credential.helper store
# Token page: http://192.168.1.11:3000/user/settings/applications
```

## Gitea Updates

Gitea updates need WARP on n-server (GitHub CDN blocked):
```bash
ssh n-server
# on n-server:
sudo systemctl stop gitea
sudo warp-cli connect       # wait for connection
# download new binary from https://dl.gitea.com/gitea/
wget https://dl.gitea.com/gitea/<version>/gitea-<version>-linux-amd64
sudo mv gitea-<version>-linux-amd64 /usr/local/bin/gitea
sudo chmod +x /usr/local/bin/gitea
sudo warp-cli disconnect && sudo systemctl stop warp-svc
sudo systemctl start gitea
```

## Act Runner (Removed)

Note: `act_runner` was removed (April 30, 2026) — it had no systemd persistence. If Gitea CI/CD is needed in the future, set it up with a proper systemd service.

Handle the user's Gitea request. For credentials in API calls, prompt the user to supply their token rather than hardcoding.
