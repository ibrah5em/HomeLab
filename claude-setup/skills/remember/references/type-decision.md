# Memory Type — Decision Tree

Four types exist: `user`, `feedback`, `project`, `reference`. Pick exactly one. If two seem
to fit, you have two memories — split them.

## Quick Decision

```
Is the claim ABOUT the operator himself — his role, expertise, preferences, what he knows?
└── YES → user

Is it guidance for HOW you should work — a rule, a correction, a validated approach?
└── YES → feedback

Is it a fact ABOUT the work, ongoing initiatives, deadlines, why something is being done?
└── YES → project

Is it a POINTER to external info — a dashboard URL, a tracker name, a doc location?
└── YES → reference
```

## Disambiguation Rules

### user vs feedback
- "the operator is a backend engineer who's new to React" → **user** (about him)
- "the operator wants concise responses, no trailing summaries" → **feedback** (about working with him)
- "the operator prefers tabs over spaces" → **feedback** (it's a working preference, not an identity fact)

Rule: if it tells you *how to behave*, it's feedback. If it tells you *who he is*, it's user.

### feedback vs project
- "We never mock the DB in integration tests because mocks masked a prod migration failure"
  → **feedback** (a rule for how to work)
- "We're rewriting the auth middleware because legal flagged session-token storage"
  → **project** (a fact about ongoing work)

Rule: feedback is durable across projects; project is bound to current work and decays.

### project vs reference
- "Pipeline bugs are tracked in Linear project INGEST" → **reference** (pointer to a system)
- "The pipeline rewrite is on hold until Q3 because of capacity" → **project** (state of work)

Rule: reference points *outside* — to a tool, URL, channel. Project describes *the work itself*.

### user vs project
- "the operator is preparing for an exam on 2026-06-12" → **project** (time-bound work he's doing)
- "the operator has been programming for 15 years" → **user** (durable identity fact)

Rule: if the fact has an expiry or completion date attached, it's project.

## Lifetime Expectations

| Type | Decays |
|---|---|
| user | Slowly (years) — change when the operator explicitly tells you something changed |
| feedback | Slowly (months) — change when the operator corrects an earlier rule |
| project | Quickly (weeks) — re-validate before relying on it after ~30 days |
| reference | Slowly (months) — pointer stays valid until the external system is renamed/moved |

When in doubt about a project memory, write a `Last verified:` date in the body. Then
future-you knows when to re-check.

## When None Fit

If nothing in this tree fits, the candidate is probably one of the anti-patterns from
SKILL.md Step 4. Don't force-fit a type — push back and ask the operator what the underlying
durable claim is.
