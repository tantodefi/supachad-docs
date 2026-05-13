# Introduction

Chad is an always-on assistant. Not a chat agent — those exist when
you're typing at them and don't exist when you aren't. Chad exists in
between. Chad reads mail every hour, drafts replies, watches its own
budget, dreams its knowledge brain at night, and proposes
self-improvements once a week.

Three properties define the design:

## 1. Always on

Chad is a process tree, not a tab. The agent's contract with the day
is **eleven standing cron jobs**, each a one-line wrapper invocation
that exits in under a minute. Heavy work happens inside the wrapper
(Python, shell, detached `nohup` jobs); the model only sees
"do the thing the wrapper does" because re-tokenizing a long prompt
on every cron fire is expensive on a free-tier inference endpoint.
Every cron runs with `--light-context` enabled, which strips skill
and plugin frontmatter from the bootstrap and typically cuts per-fire
input tokens by 70–80%.

The cron schedule is published [here](operations.md). It is
deliberately conservative — fewer, cheaper runs beat reactive
chat-bot behavior at this layer.

## 2. Delegates safely

Anything beyond a one-shot reply is a **sub-agent spawn**. Seven
kinds today: `coder`, `researcher`, `writer`, `reviewer`, `fitness`,
`codex`, `opencode`. Each kind is a YAML manifest that pins a
binary path and a network policy preset.

Pinning the binary at the L7 proxy is the load-bearing safety
mechanism. A `reviewer` kind is allowed to GET on `api.github.com`
but not POST — meaning a compromised reviewer cannot post a
malicious review even if its prompt is hijacked. A `writer` kind
cannot reach GitHub at all. The principle is **sub-agents draft;
parents publish**.

Spawns can route to one of two execution substrates:

- **`local`** — sub-agent runs in Chad's container under the kind's
  L7 policy. Synchronous. Default for kinds that need access to
  Chad's local brain, embedded inference, or source clone.
- **`gha`** — sub-agent runs on a GitHub Actions runner per spawn.
  Async-capable. The runner is fresh, unrelated to the parent's
  filesystem. Default for kinds whose work is self-contained
  (codex, opencode).

## 3. Earns autonomy

Every irreversible action — sending mail, posting a comment,
modifying a cron, deleting a memory — passes through
**`chad-action-gate`**. The gate reads `auto-actions.json`, which
maps `{action_type, target}` pairs to one of three modes:

- `auto` — Chad performs the action immediately
- `draft` — Chad parks the action for human review
- `block` — Chad must not perform the action

Anything not listed in the policy falls through to a default of
`block`. New senders, new repos, new external services all start
blocked and earn promotion to `auto` only after the operator
demonstrates trust.

The kill switch is a single file: `touch
/sandbox/.openclaw/workspace/.auto-disabled` halts every autonomous
action regardless of policy. `rm` it to resume.

---

## How Chad differs from a chat agent

| Dimension | Typical chat agent | Chad |
|---|---|---|
| Lifecycle | Per-session | Always running |
| Trigger | Human types something | Cron, mail, GitHub issue, webhook |
| Memory | Conversation history | Workspace files + lancedb LTM + wiki + gbrain |
| Trust | Implicit (you initiated it) | Explicit policy file with per-target rules |
| Scope | One task per turn | Discrete spawns with budgets |
| Failure | Retry the prompt | Drafts the action; waits for review |

---

## What Chad is not

- **Not a chatbot.** There's a chat surface (OpenWebUI), but the
  primary work happens unattended.
- **Not multi-tenant.** One operator account, one mailbox, one
  GitHub identity. Multi-Chad scheduling is a future direction.
- **Not reproducible without infrastructure.** Chad needs Proton,
  Anthropic (optional), NVIDIA inference, and a private state repo.
  See [Reproducing](reproducing.md) for the full picture.
- **Not unsupervised.** The autonomy roadmap is gradual on purpose.
  New action types and new senders go through human review before
  they auto-anything.

---

## Where to go next

- **Architecture overview** → [architecture.md](architecture.md) —
  the three rings, the spawn flow, the substrate split.
- **Memory stack** → [memory.md](memory.md) — what each store is for
  and where each fact belongs.
- **Orchestrator + sub-agents** → [orchestrator.md](orchestrator.md)
  — kinds, manifests, prompt templates, how to add a new kind.
- **Substrates** → [substrates.md](substrates.md) — local vs GHA,
  provider routing, async mode.
- **Autonomy** → [autonomy.md](autonomy.md) — the action gate, the
  policy file, the kill switch.
