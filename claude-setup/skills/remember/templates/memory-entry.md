# Memory Entry Skeletons

Copy the block matching the type chosen in Step 2, fill in placeholders, write to
`/home/homelab/.claude/projects/-home-homelab-HomeLab/memory/<slug>.md`.

Frontmatter fields are required for all types:
- `name:` — kebab-or-snake-case slug, matches filename
- `description:` — one specific line that future-Claude reads to decide relevance
- `metadata.type:` — one of `user`, `feedback`, `project`, `reference`

---

## user

For facts about the operator himself — role, expertise, knowledge, durable preferences about
his identity (not how to work with him).

```markdown
---
name: <slug>
description: <One-line summary of who/what about the operator — specific, not "user notes">
metadata:
  type: user
---

<Plain prose. State the fact. Add context only if it changes how you'd work with him.>

<Optional: link to related memories with [[other-slug]].>
```

---

## feedback

For rules about how to work with him — corrections AND validated approaches. Always include
**Why** and **How to apply** so future-you can judge edge cases.

```markdown
---
name: <slug>
description: <The rule in one line — e.g. "Never mock the DB in integration tests">
metadata:
  type: feedback
---

<The rule itself, one short line.>

**Why:** <Reason given — past incident, strong preference, validated experience.>

**How to apply:** <When/where this kicks in. What contexts it does and doesn't cover.>

<Optional: [[link-to-related-memory]]>
```

---

## project

For facts about ongoing work — initiatives, deadlines, why something is being done. These
decay fast; include dates and a re-check signal.

```markdown
---
name: <slug>
description: <One line: the fact or decision, with a date if time-bound>
metadata:
  type: project
---

<The fact or decision in one short line.>

**Why:** <The motivation — constraint, deadline, stakeholder ask.>

**How to apply:** <How this should shape suggestions or decisions you make.>

Last verified: <YYYY-MM-DD>

<Optional: [[link-to-related-memory]]>
```

---

## reference

For pointers to external systems — URLs, tracker names, channels, dashboards. The body is
just enough to know what's there and when to look.

```markdown
---
name: <slug>
description: <What this points to and when to use it>
metadata:
  type: reference
---

**Where:** <URL / tool name / channel>

**What's there:** <One sentence on what you'll find>

**When to check:** <The contexts that should send you here>

<Optional: [[link-to-related-memory]]>
```

---

## Slug Naming Conventions

Match the existing pattern in MEMORY.md:
- Scope first if there's a clear domain: `xserver_known_non_issues`, `aide_setup`
- Use snake_case for compound scopes, kebab-case is fine too — be consistent within a
  theme (don't mix `x-server_X.md` and `xserver_Y.md`)
- Keep slugs under ~30 chars; the description carries the detail

## MEMORY.md Line Format

After writing the file, add (or edit) the index line in MEMORY.md:

```
- [Human Title](slug.md) — one-line hook
```

The hook should answer "when would I want to read this?" — not restate the title.
