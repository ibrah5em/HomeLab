# Naming Conventions & Style Guide

## File Naming

| Artifact | Convention | Example |
|---|---|---|
| Command | `kebab-case.md` | `nginx-logs.md` |
| Agent | `kebab-case.md` | `x-server.md` |
| Skill directory | `kebab-case/` | `new-service/` |
| Skill file | `SKILL.md` (always caps) | `SKILL.md` |
| Template | `kebab-case.md` | `nginx-site-conf.md` |
| Reference | `kebab-case.md` | `ufw-rules.md` |

## Command Naming Rules

Commands map 1:1 to what the user types: `commands/foo.md` → `/foo`.

**Prefix by server when ambiguous:**
- `x-docker.md` → `/x-docker` (Docker on x-server)
- `n-pihole.md` → `/n-pihole` (Pi-hole on n-server)

**Use verb-noun for action commands:**
- `ssl-check.md` → `/ssl-check`
- `wg-add-peer.md` → `/wg-add-peer`

**Use noun for dashboard/view commands:**
- `status.md` → `/status`
- `logs.md` → `/logs`
- `vpn.md` → `/vpn`

## Agent Naming Rules

Agents are named by domain, not action:
- `x-server.md` — the x-server expert
- `n-server.md` — the n-server expert
- `security.md` — security auditor
- `deploy.md` — deployment specialist

Don't create agents named after specific services (not `nginx-agent.md`) — the server agents handle individual services.

## Skill Naming Rules

Skills are named by workflow:
- `new-service/` — adding a new Docker service end-to-end
- `security-audit/` — full structured audit
- `extend-claude/` — extending the .claude project (this skill)

## Content Style

### Commands
- First line: `# /<name> — <Short Descriptive Title>`
- Second line: one-sentence description
- Third line: `**User's request:** $ARGUMENTS`
- Sections: `## Context`, `## Operations`, `## Output`
- Tone: precise, imperative ("Run this command", "Flag if...")

### Agents
- YAML frontmatter: `name` + `description` (required), `model` (required — see below)
- Body opens with: "You are an expert [role] specializing in [domain]."
- Sections: `## Your Knowledge Base`, `## Critical Rules`, `## Your Behavior`
- Tone: first person ("You are...", "You always...", "You remind...")

#### Model Selection (required field)

Every agent declares its preferred model in frontmatter. The main session can't auto-switch
models mid-conversation, but subagents run on whatever model they declare regardless of the
orchestrator's model — so model routing happens at the agent boundary.

```yaml
---
name: <agent>
description: <...>
model: sonnet   # or opus, or haiku
---
```

Pick by task profile, not by importance:

| Model | Use for | Example agents |
|---|---|---|
| **sonnet** | Procedural ops, lookups, log correlation, well-defined workflows. Default for most homelab agents. | `deploy`, `n-server`, `x-server`, `monitoring` |
| **opus** | Multi-step reasoning, security tradeoffs, threat analysis, architecture decisions, ambiguous debugging | `security` |
| **haiku** | Pure lookup / classification with zero reasoning. Rare — only when sonnet feels like overkill. | (none currently) |

Default to **sonnet** when in doubt. Bump to **opus** if the agent regularly needs to weigh
multiple options, reason about tradeoffs, or chase ambiguous root causes. The per-spawn
override on the Agent tool (`model:` parameter) wins over frontmatter, so one-off escalation
is always available without editing the file.

### CLAUDE.md
- Organized by server (## X-SERVER, ## N-SERVER, ## MY SYSTEM)
- Tables for structured data (services, ports, paths)
- Code blocks for exact commands
- "Critical Notes" section per server for gotchas
- Bottom section: "Key Gotchas (Burned Before)" — flat bullet list

## Infrastructure Vocabulary

Use these exact names (not alternatives):

| Use this | Not this |
|---|---|
| x-server | X-Server, xserver, the server |
| n-server | N-Server, nserver, the other server |
| `nginx-ssl` | nginx, the nginx container |
| `docker_management` | docker-management, management network |
| `kids-app` | kids-app-kids, the kids-app container (the domain is kids.example.net but the container is just `kids-app`) |
| `~/docker/` | /docker/, docker compose folder |
| `before.rules` | iptables rules, ufw rules |
| `wg0` | wireguard, the VPN interface |
| pihole-FTL | Pi-hole FTL, ftl |

## SSH Command Style

Always use the SSH config alias:
```bash
# Correct
ssh x-server "command"
ssh n-server "command"

# Wrong
ssh homelab@192.168.1.10 -p 2222 "command"
ssh -i ~/.ssh/x-server-new -p 2222 homelab@192.168.1.10 "command"
```

## Docker Command Style

Always specify compose file path:
```bash
# Correct
docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload

# Wrong (ambiguous if run from wrong directory)
docker compose exec nginx nginx -s reload
```

Always use `-T` flag with `docker compose exec` (no TTY assumption):
```bash
# Correct
docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -t

# Wrong (will fail in scripts/cron)
docker compose -f ~/docker/docker-compose.yml exec nginx nginx -t
```
