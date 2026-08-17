# Command Template

A slash command is a Markdown file that acts as a **prompt template** — when the user types `/<name>`, Claude reads this file and executes the instructions inside it. The `$ARGUMENTS` variable captures anything the user typed after the command name.

---

## Minimal Command Structure

```markdown
# /<command-name> — Short Title

One sentence describing what this command does and when to use it.

**User's request:** $ARGUMENTS

## Context

[What Claude needs to know to execute this command — server details, paths, gotchas.]

## Operations

[The actual commands / logic / SSH calls to run.]

## Output

[What to show the user after completion — format, what to highlight.]
```

---

## Full Annotated Template

```markdown
# /<command-name> — <Short Descriptive Title>

<One sentence: what this command does. Be specific about the scope — which server, which service.>

**User's request:** $ARGUMENTS

## Context

<Everything Claude needs to know about the service/infra this command touches.>

<Include:>
- SSH connection (e.g., `ssh x-server`)
- Relevant file paths on the server
- Architecture notes (e.g., "nginx runs in Docker as nginx-ssl")
- Critical safety rules (e.g., "NEVER restart nginx, always reload")
- Known gotchas for this service

## Operations

<The actual work. Be concrete — exact bash commands, not descriptions.>

### If user asks to [action A]:
```bash
<exact command>
```

### If user asks to [action B]:
```bash
<exact command>
```

<For ambiguous requests, instruct Claude to ask before running anything destructive.>

## Output

<Tell Claude what to show the user:>
- What success looks like
- What to highlight (errors, warnings, key values)
- Whether to run a follow-up verification command
```

---

## Homelab-Specific Conventions

### SSH Invocation
Always use the SSH alias from `~/.ssh/config`:
```bash
ssh x-server "command"      # not: ssh homelab@192.168.1.10 -p 2222
ssh n-server "command"
```

### Docker Commands on x-server
```bash
# Compose commands — always specify the compose file path
docker compose -f ~/docker/docker-compose.yml <subcommand>

# NEVER restart nginx — always reload
docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -s reload

# Test before reload
docker compose -f ~/docker/docker-compose.yml exec -T nginx nginx -t

# Always use -T flag with exec in scripts (no TTY)
docker compose -f ~/docker/docker-compose.yml exec -T <service> <cmd>
```

### Sensitive Operations Pattern
For any destructive or irreversible command, follow this pattern:
```markdown
## ⚠️ Before running this command:
Show the user what will happen and ask for confirmation.
Only proceed after they confirm.
```

### Output Format Pattern
End commands with a verification step:
```markdown
After executing, run:
```bash
<verification command>
```
And report the result to confirm success.
```

---

## Real Examples

### Minimal (one-purpose command)
```markdown
# /wg-show — WireGuard Peer Status

Show current WireGuard VPN status including connected peers and handshake times.

**User's request:** $ARGUMENTS

```bash
ssh x-server "sudo wg show"
```

Report: interface name, peer count, each peer's last handshake and bytes transferred.
Flag any peer with no handshake in the last 3 minutes as potentially disconnected.
```

### Full (multi-operation command)
See `/commands/nginx.md` or `/commands/docker.md` for complete examples.
