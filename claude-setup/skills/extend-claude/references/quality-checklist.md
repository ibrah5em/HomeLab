# Quality Checklist

Run this before presenting any new artifact to the operator.

---

## All Artifacts

- [ ] File is at the correct path (see `conventions.md`)
- [ ] Filename is kebab-case (except `SKILL.md`)
- [ ] No placeholder text left unfilled (`<name>`, `TODO`, `...`)
- [ ] No secrets or credentials hardcoded
- [ ] Infrastructure names use the exact vocabulary from `conventions.md`
- [ ] SSH commands use config aliases (`ssh x-server`, not raw IP)

---

## Commands

- [ ] First line follows format: `# /<name> — <Title>`
- [ ] `**User's request:** $ARGUMENTS` present (if command takes arguments)
- [ ] All bash commands are exact and runnable (not pseudocode)
- [ ] Docker compose commands specify `-f ~/docker/docker-compose.yml`
- [ ] Docker exec commands use `-T` flag
- [ ] Destructive operations include a "show plan → confirm → execute" instruction
- [ ] Output section tells Claude what to report to the user
- [ ] Any verification step included after the operation

---

## Agents

- [ ] YAML frontmatter present with `name`, `description`, and `model`
- [ ] `model` is one of `sonnet`, `opus`, or `haiku` (see conventions.md → Model Selection)
- [ ] Description is specific enough to auto-trigger (not generic)
- [ ] Description covers 2-3 specific trigger phrases
- [ ] Body opens with "You are an expert..."
- [ ] "Critical Rules You Always Follow" section present
- [ ] At least one rule covers confirmation before destructive ops
- [ ] At least one rule covers verification after changes
- [ ] Agent reminds the operator to update server docs after significant changes
- [ ] "Your Behavior" section closes the agent

---

## Skills

- [ ] `SKILL.md` present in skill directory
- [ ] Frontmatter has `name` and `description`
- [ ] Description is specific and slightly "pushy"
- [ ] Numbered steps are clear and complete
- [ ] References to template/reference files use exact relative paths
- [ ] Template/reference files actually exist if referenced
- [ ] Output step specifies how to deliver the result

---

## CLAUDE.md Updates

- [ ] New content placed under the correct server section
- [ ] New service added to the services table (with port, access, notes)
- [ ] New key path added to the Key Paths section
- [ ] Any new gotcha added to "Key Gotchas (Burned Before)" at the bottom
- [ ] No existing content deleted accidentally
- [ ] "Last updated" line updated if present

---

## Infrastructure Accuracy (x-server)

When any artifact touches x-server Docker/nginx:
- [ ] Uses `docker_management` network name
- [ ] Certbot commands include `--network docker_management`
- [ ] nginx reload uses `nginx -s reload`, not restart
- [ ] Build commands include `DOCKER_BUILDKIT=0`
- [ ] `iptables: false` implications noted if touching firewall rules
- [ ] `before.rules` mentioned as the correct place for NAT/FORWARD rules

## Infrastructure Accuracy (n-server)

When any artifact touches n-server:
- [ ] Pi-hole commands use v6 syntax (`pihole-FTL --config`, not env vars)
- [ ] WARP procedure included if operation needs GitHub access
- [ ] WARP disconnect reminder included after any WARP workflow
- [ ] `systemd-resolved` status noted if DNS-related
- [ ] "100% dark to WAN" principle respected (no public port instructions)
