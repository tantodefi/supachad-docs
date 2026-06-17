# Autonomy & the action gate

The single most-cited safety mechanism in the design is the action
gate. Every irreversible external action passes through it — no
exceptions. The gate is a small Bash binary plus a JSON policy file;
both are operator-readable, neither requires understanding the
agent's internals to audit.

## The mental model

There are three modes a given action can be in:

- **`auto`** — Chad performs the action immediately, increments a
  counter, appends to the audit log, moves on.
- **`draft`** — Chad prepares the action and parks it for human
  review under a `### Draft replies (review before sending)` section
  in today's memory. The work is done; the ship is gated.
- **`block`** — Chad does not perform the action. It is recorded as
  a refusal in the audit log so patterns of attempted-but-blocked
  actions surface in the weekly review.

Anything not listed in the policy file falls through to a default of
`block`. New action types and new senders all start blocked; promotion
to `draft` and then `auto` is the autonomy ratchet.

## The policy file

`/sandbox/.openclaw-data/auto-actions.json` is the single source of
truth. A trimmed shape:

```json
{
  "_meta": {
    "kill_switch_file": "/sandbox/.openclaw/workspace/.auto-disabled",
    "audit_log": "/sandbox/.openclaw-data/state/auto-action-log.jsonl",
    "modes": {
      "auto":  "Chad performs the action immediately.",
      "draft": "Chad drafts the action and parks it for human review.",
      "block": "Chad must not perform the action."
    }
  },

  "_budgets": {
    "email_reply":     20,
    "email_send_new":   5,
    "github_pr_open":   1,
    "github_pr_merge":  0,
    "spawn_subagent":  24,
    "spawn_premium":    8
  },

  "email_reply": {
    "_default":              "block",
    "operator@example.com":  "auto",
    "admin@example.com":     "auto",
    "agent@example.com":     "block"
  },

  "github_pr_merge":         { "_default": "block" },
  "spawn_subagent":          { "_default": "auto" },
  "memory_curator_propose":  { "_default": "auto" },
  "memory_apply_proposal":   { "_default": "draft" },
  "memory_snapshot_rollback":{ "_default": "block" }
}
```

Per-action-type config has a `_default` and any number of per-target
overrides. `chad-action-gate check email_reply operator@example.com`
returns `auto`; the same check against an unknown sender returns
`block`.

## The kill switch

A single file controls the whole policy:

```bash
# Halt all autonomous actions immediately
ssh openshell-chad 'touch /sandbox/.openclaw/workspace/.auto-disabled'

# Resume
ssh openshell-chad 'rm /sandbox/.openclaw/workspace/.auto-disabled'
```

When the file exists, every `chad-action-gate check` returns
`killed` regardless of policy. Wrappers fall through to draft mode
and the next session sees a banner.

## Daily budgets

The `_budgets` map sets per-action-type daily caps. Counters live in
`/sandbox/.openclaw-data/state/auto-action-counters.json` and reset
at UTC midnight (the same boundary used by the token budget at
`budget.json`).

When an action's counter is at the cap, the gate returns `budget`
(exit 3). Wrappers fall through to draft mode — the action is
queued, not refused; it'll get reviewed in the morning.

## The audit log

Every gate decision lands in
`/sandbox/.openclaw-data/state/auto-action-log.jsonl` with one JSON
record per line:

```json
{"ts":"2026-05-06T13:42:18Z","action":"email_reply","target":"operator@example.com","result":"auto","message_id":"...","detail":"sent"}
```

Patterns visible in this log:

- A spike in `result: block` for a sender suggests onboarding —
  consider promoting them to `draft` or `auto`.
- A spike in `result: budget` suggests the caps are too low for the
  current workload.
- `result: killed` records when the kill switch was active and what
  Chad would have done in its absence.

## Two safe-listed apply paths

Two specific wrappers can *apply* changes that wouldn't otherwise
make it past the gate, both within hard guardrails:

### `chad-proposal-apply`

Reads the latest proposals JSON block emitted by `chad-budget-audit`
and applies a narrow safe-list of cron tuning changes:

- Field must be in `{ timeoutSeconds, maxOutputTokens }`
- New value must be within ±2× the current value
- Last-run must have been ok
- Gated by `chad-action-gate chad_self_modify_cron <cron-name>`

Anything riskier (new kind manifest, schedule change, code edit)
stays draft-only.

Memory consolidation is draft-only the same way: the curator (and the
`memory-curator.jsx` workflow) propose changes behind an `Approval`;
the operator applies. Pre-mutation snapshots make any apply reversible.

## The autonomy gradient

Earning autonomy gradually is the core governance model, not a feature
backlog: each action sits at a trust level, and a level only rises when
the audit log shows the judgment is reliable enough. Today's policy has
very few `auto` entries by design. The "Earned" column is the ceiling a
given action can reach as trust accrues — the gate, not a ship date:

| Action | Today | Earned ceiling |
|---|---|---|
| email_reply (allowlisted senders) | auto | auto |
| email_reply (everyone else) | block | draft (after triage maturity) |
| spawn_subagent | auto | auto |
| spawn_premium (allowlisted) | auto (capped) | auto (capped) |
| github_comment (chad-state) | auto | auto |
| github_comment (other repos) | block | draft |
| github_pr_open | block | draft |
| github_pr_merge | block | block (likely permanent) |
| chad_self_modify_skill | draft | auto for narrow safe-list |
| chad_self_modify_cron | draft | auto for narrow safe-list (already partial) |
| chad_self_modify_identity | draft | block (operator-only) |

The gradient is intentional: each promotion needs evidence the
relevant judgment is reliable enough for that surface. The audit log
is the evidence ledger.
