---
name: extend-claude
description: Use this skill whenever the operator wants to extend his .claude homelab project — adding new slash commands, sub-agents, skills, config files, or folders. Triggers on any request like "add a command for X", "create an agent that...", "make a skill for...", "add a new section to .claude", "I want Claude to know about Y", or any request to modify, expand, or reorganize the .claude project structure. Also triggers when he wants to update CLAUDE.md with new server info, add a new server, or change how existing commands/agents behave.
---

# extend-claude — Skill for Extending the .claude Homelab Project

This skill builds new components for the operator's `.claude` project, which lives at `~/.claude/` (or inside a project directory). It knows the conventions, the file formats, and the infrastructure context.

## Quick Orientation

```
.claude/
├── CLAUDE.md                          ← Global context (always loaded)
├── commands/                          ← Slash commands (/name)
│   └── <name>.md
├── agents/                            ← Sub-agents (use via /agent:<name> or auto-routed)
│   └── <name>.md
└── skills/                            ← Skills (SKILL.md + bundled resources)
    └── <skill-name>/
        ├── SKILL.md
        ├── templates/
        └── references/
```

## Step 1 — Identify What to Build

Ask the user (or infer from context) which artifact type is needed:

| User says... | Build this |
|---|---|
| "add a command for X" | `commands/<name>.md` |
| "create an agent that handles X" | `agents/<name>.md` |
| "make a skill for X workflow" | `skills/<name>/SKILL.md` |
| "Claude should always know about X" | Update `CLAUDE.md` |
| "add config for X" | `config/<name>.md` or entry in `CLAUDE.md` |
| "new folder for X" | Scaffold the folder + placeholder files |

If the type is ambiguous, use this rule:
- **Command** → one-shot operation the user invokes explicitly (`/nginx reload`)
- **Agent** → persistent expert persona for a domain, invoked for complex multi-step tasks
- **Skill** → multi-step workflow with templates/references, triggered by context
- **CLAUDE.md update** → new infrastructure fact that every command/agent should know

## Step 2 — Gather Context

Before writing anything, collect:

1. **Name** — short, kebab-case, describes the action or domain
2. **Purpose** — what does this artifact do / when is it used?
3. **Server/service scope** — x-server, n-server, WSL, or cross-system?
4. **Key commands** — what bash commands / SSH operations does it need?
5. **Gotchas** — any Syria-specific blocks, non-standard configs, known failure modes?

For commands and agents: pull relevant facts from `CLAUDE.md` and the server docs. Don't make the user repeat context they've already provided.

## Step 3 — Write the Artifact

Read the matching template before writing:

| Artifact | Template |
|---|---|
| Command | `templates/command.md` |
| Agent | `templates/agent.md` |
| Skill | `templates/skill.md` |
| CLAUDE.md section | `references/claude-md-conventions.md` |

Then write the file and place it at the correct path. See `references/conventions.md` for naming and style rules.

## Step 4 — Validate

Run the quality checklist from `references/quality-checklist.md` before presenting the output.

## Step 5 — Present & Install

Show the user:
1. The file path where it goes
2. The full file content
3. How to invoke it (e.g., `/new-command` or `use the x-server agent`)
4. Any related files that should be updated (e.g., CLAUDE.md if a new service was added)

If multiple files were created, zip them and use `present_files`.

---

## File Paths Reference

All paths are relative to wherever `.claude/` lives (usually `~/.claude/` or `<project>/.claude/`):

```
commands/<name>.md          → invoked as /<name> in Claude Code
agents/<name>.md            → invoked as /agent:<name> or auto-routed
skills/<name>/SKILL.md      → auto-triggered by context matching description
CLAUDE.md                   → always loaded, global context
```

No registration needed — Claude Code auto-discovers all files in these directories.
