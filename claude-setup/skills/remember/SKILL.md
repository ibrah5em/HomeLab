---
name: remember
description: >
  Use this skill ONLY when the operator explicitly asks to save, update, or remove
  something from auto-memory. Triggers on "remember that...", "save this to memory",
  "/remember X", "add a memory about X", "update the memory on X", "forget X",
  "drop the memory about X". Do NOT auto-trigger on save-worthy moments — that's
  a separate decision the user owns.
---

# remember — Curated Saves to Auto-Memory

Memory is most useful when it's small, deduped, and well-linked. Adding a new file every
time a fact comes up degrades the index — within a few months, MEMORY.md becomes a list of
near-duplicates and the system loses the ability to surface the right entry at the right
time. This skill enforces a five-check pipeline so each save is a deliberate edit to the
memory store, not a dump.

The memory store lives at
`/home/homelab/.claude/projects/-home-homelab-HomeLab/memory/`. The directory already
exists — write into it directly with the Write tool. Never `mkdir` it.

## Step 1 — Extract the Claim

State the candidate memory back to the operator in one sentence before doing anything else. If
the request is vague ("remember what we just talked about"), pull out the specific fact you
plan to save and confirm it. Don't paraphrase loosely — memory is read literally in future
sessions, so the wording you commit to is the wording that lands.

Convert relative dates to absolute. "Last Thursday" → `2026-05-08`. "We're freezing
deploys after Thursday" → `2026-05-15`. If today's date isn't obvious from context, check
the system prompt's `currentDate` block.

## Step 2 — Classify the Type

Read `references/type-decision.md` and pick exactly one type: `user`, `feedback`, `project`,
or `reference`. The decision tree is short. If two types seem to fit, the entry is probably
two memories — split it.

## Step 3 — Check for Duplicates (Update > Create)

Before writing a new file, read `MEMORY.md` and look for overlap. For every candidate, ask:
"Is there an existing memory whose `description` or slug overlaps this topic?"

If yes:
- **Refining a fact in the same memory** → Read the existing file, edit in place, update its
  `description:` line if the scope changed. Do NOT create a second file.
- **Adding a new fact that's a sibling under the same theme** → Append to the existing file
  under a new heading rather than spawning a near-duplicate.
- **Contradicts an existing memory** → Update the old one (don't leave stale claims sitting
  next to the new truth). Note inside the file what changed if it matters historically.

If no existing memory covers this:
- Pick a short kebab-case slug. Use the pattern `<scope>_<topic>.md` to match existing
  naming (`xserver_known_non_issues.md`, `aide_setup.md`). The slug also goes in `name:`.
- Confirm the filename isn't already taken via `ls` on the memory dir.

## Step 4 — Refuse Anti-Patterns

Do NOT save the following, even if the operator asks:

- Code patterns, conventions, architecture, file paths derivable from the repo
- Git history facts, who-changed-what summaries
- Debugging recipes ("the fix is X") — the fix is in the code, the why is in the commit
- Anything already documented in `.claude/CLAUDE.md` or the server docs
- Current-conversation state, in-progress task details, ephemeral context
- Activity logs, PR lists, or summaries of "what I did this week"

If the operator explicitly asks to save one of these, push back once: ask what was *surprising*
or *non-obvious* about it, and save that distilled claim instead. If he insists, save it
but flag the limitation in the body (e.g. "User asked to save this snapshot; recheck via
`git log` before relying on it after [DATE]").

## Step 5 — Write the Entry

Read `templates/memory-entry.md` for the frontmatter skeleton with per-type body shapes.
Fill it in and write the file.

Key requirements:
- Frontmatter `name:` matches the filename slug exactly
- `description:` is one specific line — this is what surfaces in future relevance decisions,
  so make it concrete, not "notes about X"
- `metadata.type:` is one of the four valid types
- Body opens with the rule/fact in one line for `feedback` and `project` types, then
  `**Why:**` and `**How to apply:**` sub-lines (per the system prompt's body structure)
- Link related memories with `[[slug]]` — use existing slugs in MEMORY.md, and don't worry
  if a link points at a slug that doesn't exist yet (it's a marker for future writes)

## Step 6 — Update MEMORY.md

`MEMORY.md` is the index, never a memory itself. Add (or update) one line per entry, under
~150 chars:

```
- [Human Title](file-slug.md) — one-line hook describing when to use it
```

Keep entries grouped by theme if helpful, but don't impose structure that isn't there yet.
Past line 200 gets truncated, so prune the index when it bloats — if two adjacent index
lines describe overlapping memories, that's a Step 3 violation, fix it.

Never write the memory body into MEMORY.md directly.

## Step 7 — Forget Path (Remove or Supersede)

If the user said "forget X" or "drop the memory about X":

1. Find the entry by description match in MEMORY.md
2. Confirm with the user which specific file before deleting ("You mean `aide_setup.md`?")
3. Delete the file
4. Remove its line from MEMORY.md

Do not delete a memory because you *think* it's stale — staleness is handled by reading
the current code/server state when the memory is invoked, not by pre-emptive cleanup here.
The audit/curate workflow is a separate skill (not built yet).

## Output

Present to the operator:
1. The exact file path written (or deleted)
2. The full frontmatter + body of the new/updated entry
3. The line added to MEMORY.md
4. Any related memories you noticed during Step 3 that might be worth a follow-up edit
   (don't edit them silently — flag them)
