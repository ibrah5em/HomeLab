# CLAUDE.md Conventions

`CLAUDE.md` is the global context file — always loaded into every Claude Code session in the project. Keep it accurate, structured, and scannable.

---

## Top-Level Structure

```markdown
# the operator's Home Lab — Claude Code Project

<One paragraph: what this project is, what's in it.>

---

## 🗺️ Network Topology
## 🖥️ X-SERVER (192.168.1.10)
## 🖥️ N-SERVER (192.168.1.11)
## 💻 MY SYSTEM (WSL2)
## 🔑 Key Gotchas (Burned Before)
## 📋 Common Workflows
```

---

## Adding a New Service (x-server)

Find the X-SERVER section → Services table → add a row:

```markdown
| **ServiceName** | Docker (`container-name`) | domain.tld or :PORT (LAN/VPN) | Brief note |
```

Find "Key Paths" under X-SERVER → add:
```markdown
<service> config:    ~/docker/<service>/
<service> data:      ~/docker/<service>/data/
```

If the service has a known gotcha → add to "Key Gotchas":
```markdown
- <What went wrong> — <how to avoid it / fix it>
```

---

## Adding a New Service (n-server)

Find the N-SERVER section → Services table → add a row:

```markdown
| **ServiceName** | PORT | 🏠 LAN | What it does |
```

Add to "Key Paths" under N-SERVER.

If WARP is needed to install/update → add to "Critical Notes" under N-SERVER:
```markdown
- ServiceName update: needs WARP active (GitHub blocked) — follow WARP procedure
```

---

## Adding a New Server

Add a new top-level section following the same pattern as X-SERVER and N-SERVER:

```markdown
## 🖥️ <SERVER-NAME> (<IP>)

**Role:** <one sentence>

### SSH
```bash
ssh <alias>    # uses ~/.ssh/config → port XXXX, key ~/.ssh/<key>
```
Config: `HostName <IP> | Port XXXX | User homelab | IdentityFile ~/.ssh/<key>`

### Services
...

### Key Paths
...

### Critical Notes
...
```

Also:
1. Update the Network Topology diagram
2. Add the new server's SSH config to the SSH Config section
3. Add any relevant gotchas to the bottom section

---

## Adding a Workflow

Find "## 📋 Common Workflows" → add a new `###` subsection:

```markdown
### <Workflow Name>
1. Step one
2. Step two
3. Step three
```

---

## Updating a Gotcha

The bottom section "Key Gotchas (Burned Before)" is a flat bullet list. Add new entries at the end:

```markdown
- **<Concise problem statement>** — <one-line solution or workaround>
```

Examples of good gotcha format:
```markdown
- **`docker compose restart` doesn't pick up new volumes** — use `up -d` instead
- **Certbot needs `--network docker_management`** — default bridge has no outbound
- **Pi-hole v6 ignores env vars** — use `pihole-FTL --config key value`
```

---

## Style Rules

- Use emoji headers (🖥️, 🌐, 🔒, etc.) for major sections — they're already established
- Tables for services and ports (scannable at a glance)
- Code blocks for exact commands, paths, configs
- ⚠️ prefix for warnings inside prose
- Keep "Key Gotchas" as a flat list — not nested, not categorized
- Update the `> Last updated:` date at the top of the file if it exists
