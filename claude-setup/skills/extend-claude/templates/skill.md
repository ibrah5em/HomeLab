# Skill Template

A skill is a **directory** containing a `SKILL.md` and optional bundled resources. Skills are auto-triggered when the user's request matches the `description` field — Claude reads the SKILL.md and follows its workflow before responding.

Use skills for **multi-step workflows** that benefit from templates, references, or reusable scripts. Use commands for one-shot operations.

---

## Directory Structure

```
skills/<skill-name>/
├── SKILL.md              ← Required. Frontmatter + workflow instructions.
├── templates/            ← Optional. Reusable file templates.
│   └── <template>.md
└── references/           ← Optional. Docs loaded into context as needed.
    └── <topic>.md
```

---

## SKILL.md Structure

```markdown
---
name: <skill-name>
description: <When to trigger. What it does. Be specific and slightly pushy.>
---

# <Skill Title>

<One paragraph: what this skill does and why it exists.>

## Step 1 — <First Step Name>

<Instructions for this step.>

## Step 2 — <Second Step Name>

<Instructions, with reference to bundled files where relevant:>
Read `templates/<template>.md` before writing any output.

## Step 3 — <Third Step Name>

...

## Output

<What to produce and how to present it.>
```

---

## Annotated Full Template

```markdown
---
name: <kebab-case-name>
description: Use this skill whenever [specific trigger phrases or contexts]. 
  Handles [what it does]. Also triggers when [secondary triggers].
---

# <Skill Name> — <Short Description>

<Brief intro: what problem this skill solves, when to use it.>

## Step 1 — Gather Intent

<What to ask or infer before starting. What information is needed.>

Required inputs:
- [Input 1]
- [Input 2]

## Step 2 — [Main Action]

<Core workflow. Reference templates/references as needed:>

Read `templates/<name>.md` for the output format before writing anything.

For [variant A]:
<instructions>

For [variant B]:
<instructions>

## Step 3 — Validate

<Quality checks. What to verify before presenting output.>

Checklist:
- [ ] [Check 1]
- [ ] [Check 2]

## Step 4 — Present

<How to deliver the result — file, inline, zip, etc.>

If files were created, use `present_files` to deliver them.
Always show the user the file path and how to use what was created.
```

---

## Bundled Resource Patterns

### Templates directory
Store file templates that this skill generates:
```markdown
# In SKILL.md:
Read `templates/nginx-site.conf` and use it as the base for the new site config.
Fill in [SERVER_NAME], [PROXY_PASS], and [CERT_PATH] with the user's values.
```

### References directory
Store reference docs loaded on demand:
```markdown
# In SKILL.md:
Before writing any UFW rules, read `references/ufw-before-rules.md` 
for the current before.rules structure and where to insert new rules.
```

### When to use bundled resources vs inline
- **Inline** — if it's <20 lines and always needed → put it in SKILL.md
- **Template file** — if it's a reusable file structure Claude fills in
- **Reference file** — if it's a large doc consulted conditionally

---

## Homelab Skill Examples

### Good skill candidates
- "new-service" — full workflow for adding a Docker service to x-server (nginx config + docker-compose + SSL + docs update)
- "security-audit" — structured audit across both servers with report output
- "new-wireguard-peer" — generate keys + config + update wg0.conf workflow
- "backup-verify" — verify backups on both servers, test restore path

### Not a skill (use command instead)
- "show docker containers" → `/docker` command
- "reload nginx" → `/nginx` command
- "check pihole status" → `/pihole` command

---

## Description Writing

The description is the trigger mechanism. Be specific:

```yaml
# Good
description: >
  Use this skill whenever the operator wants to add a new Docker service to x-server — 
  creating the compose file, nginx reverse proxy config, SSL cert, and documentation 
  update in one workflow. Triggers on "add service", "deploy new app", "new container", 
  "set up X on x-server", or any request to deploy something new that needs nginx + SSL.

# Bad  
description: Deploy things to x-server.
```
