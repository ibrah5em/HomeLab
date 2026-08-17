# Agent Template

A sub-agent is a Markdown file with **YAML frontmatter** that defines a specialized expert persona. When invoked (via `/agent:<name>` or auto-routed), Claude adopts the system prompt in the file body for the duration of the task.

---

## Structure

```markdown
---
name: <agent-name>
description: <When to use this agent. Be specific — what tasks, what domain, what server.>
model: <sonnet | opus | haiku>
---

<System prompt body — this is who Claude becomes when the agent is invoked.>
```

The **`description`** field controls when Claude auto-selects this agent. Make it specific and slightly "pushy" — Claude under-triggers agents by default.

The **`model`** field is required. See `references/conventions.md` → "Model Selection" for
the picking rule. Short version: default to `sonnet`; use `opus` for agents that regularly
need to weigh tradeoffs or chase ambiguous problems; `haiku` is rarely the right call.

---

## Annotated Template

```markdown
---
name: <kebab-case-name>
description: <Expert agent for [domain]. Use when [specific triggers: user asks about X, needs to do Y on z-server, requests Z operation]. Handles [list of capabilities].>
---

You are an expert [role] specializing in [domain]. You have deep knowledge of [specific system/service] and [secondary area].

## Your Knowledge Base

### Connection
<How to connect to the relevant server(s)>

### Architecture
<Key architectural facts this agent needs — services, ports, file paths, non-standard configs>

### Services You Manage
<Table or list of services, their containers/systemd units, access methods>

### Key Paths
```
<path>    ← <what it is>
<path>    ← <what it is>
```

### Critical Rules You Always Follow
<Numbered list of safety invariants — things Claude must NEVER do or ALWAYS do in this domain>

### Known Gotchas
<Bullet list of tricky things that have burned us before>

## Your Behavior

<How this agent operates: communication style, verification habits, when to ask for confirmation, what to do when uncertain, what to remind the user about after changes>
```

---

## Homelab-Specific Patterns

### Server-Scoped Agent
For agents focused on one server:
```markdown
---
name: x-server
description: Expert agent for x-server operations...
---

You are an expert systems operator for the operator's x-server at 192.168.1.10.
```

### Cross-Server Agent
For agents that need both:
```markdown
You have SSH access to both servers:
- x-server: `ssh x-server` (192.168.1.10, Port 2222)
- n-server: `ssh n-server` (192.168.1.11, Port 2222)
```

### Safety Rules Block
Every agent that runs commands should have this section:
```markdown
### Critical Rules You Always Follow
1. For destructive operations — show plan first, get explicit confirmation
2. After any change — provide a verification command and confirm success
3. Never hardcode secrets — reference .env files or prompt user to supply
4. [Service-specific rules...]
```

### Behavior Closing
End every agent with what it reminds the user to do:
```markdown
## Your Behavior
...
- After significant changes, always remind the operator to update `~/x-server-docs.md` (or `~/n-server-docs.md`)
```

---

## Description Writing Tips

Good description (specific, includes triggers):
```
Expert agent for all n-server operations — Pi-hole DNS, Gitea, Samba, rsyslog, 
and LAN utility services on the dark-to-WAN server at 192.168.1.11. 
Use when managing DNS/ad-blocking, self-hosted git, file shares, or 
analyzing x-server logs stored on n-server.
```

Bad description (too vague):
```
Agent for the n-server.
```

---

## Real Examples

See existing agents for reference:
- `agents/x-server.md` — single-server, multi-service expert
- `agents/security.md` — cross-system, analytical role
- `agents/deploy.md` — workflow specialist with checklist behavior
